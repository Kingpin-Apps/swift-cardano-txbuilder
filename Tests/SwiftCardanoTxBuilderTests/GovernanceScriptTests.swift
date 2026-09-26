import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxBuilder

/// Scripts for script voters and proposal policies, ledger ordering of
/// withdrawal redeemers, and the itemised fee.
@Suite("Governance scripts and fee breakdown")
struct GovernanceScriptTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"
    let govActionId = GovActionID(
        transactionID: TransactionId(payload: Data(repeating: 0xAB, count: 32)), govActionIndex: 0
    )

    func anchor() throws -> Anchor {
        Anchor(
            anchorUrl: try Url("https://example.com/anchor.json"),
            anchorDataHash: AnchorDataHash(payload: Data(repeating: 0x0A, count: 32))
        )
    }

    func builder() throws -> TxBuilder {
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: { sequence.removeFirst() })
        let builder = TxBuilder(context: MockChainContext(), utxoSelectors: [selector])
        try builder
            .addInputAddress(.string(sender))
            .addOutput(try TransactionOutput(from: .list([.string(sender), .uint(500_000)])))
        builder.ttl = 123456
        return builder
    }

    func redeemer() throws -> Redeemer {
        Redeemer(data: try Unit().toPlutusData(), exUnits: ExecutionUnits(mem: 100_000, steps: 1_000_000))
    }

    func redeemerList(_ builder: TxBuilder) throws -> [Redeemer] {
        builder.useRedeemerMap = false
        guard case .list(let list)? = try builder.buildWitnessSet().redeemers else { return [] }
        return list.compactMap { $0 as? Redeemer }
    }

    @Test("A script voter's redeemer takes its place in the ledger's voter order")
    func votingScript() async throws {
        let drepScript = PlutusV3Script(data: Data("drep voting script".utf8))
        let drepHash = try plutusScriptHash(script: .plutusV3Script(drepScript))
        let committeeHash = ScriptHash(payload: Data(repeating: 0xFF, count: 28))

        let builder = try builder()
        // The committee member sorts before the DRep, whatever order they are added in.
        builder.addVote(voter: Voter(credential: .drepScriptHash(drepHash)), govActionId: govActionId, vote: .yes)
        builder.addVote(voter: Voter(credential: .constitutionalCommitteeHotScriptHash(committeeHash)), govActionId: govActionId, vote: .no)
        try builder.addVotingScript(.script(.plutusV3Script(drepScript)), redeemer: try redeemer())

        _ = try await builder.build(changeAddress: try Address(from: .string(sender)))

        let redeemers = try redeemerList(builder)
        #expect(redeemers.count == 1)
        #expect(redeemers.first?.tag == .voting)
        #expect(redeemers.first?.index == 1)
        #expect(builder.allScripts.contains(.plutusV3Script(drepScript)))
    }

    @Test("A proposal policy's redeemer points at the last proposal added")
    func proposalScript() async throws {
        let guardrail = PlutusV3Script(data: Data("guardrail script".utf8))
        let builder = try builder()
        #expect(throws: CardanoTxBuilderError.self) {
            try builder.addProposalScript(.script(.plutusV3Script(guardrail)), redeemer: try redeemer())
        }
        let rewardAccount = Data([0xE0] + Array(repeating: 0x11, count: 28))
        builder.addProposal(deposit: 100_000_000_000, rewardAccount: rewardAccount, govAction: .infoAction(InfoAction()), anchor: try anchor())
        try builder.addProposalScript(.script(.plutusV3Script(guardrail)), redeemer: try redeemer())

        let redeemers = try redeemerList(builder)
        #expect(redeemers.first?.tag == .proposing)
        #expect(redeemers.first?.index == 0)
        #expect(builder.allScripts.contains(.plutusV3Script(guardrail)))
    }

    @Test("Voting and proposing redeemers reject another tag")
    func wrongTags() throws {
        let builder = try builder()
        var wrong = try redeemer()
        wrong.tag = .mint
        #expect(throws: CardanoTxBuilderError.self) {
            try builder.addVotingScript(.script(.plutusV3Script(PlutusV3Script(data: Data([1])))), redeemer: wrong)
        }
    }

    @Test("A script withdrawal is indexed before key withdrawals, as the ledger orders them")
    func withdrawalOrder() async throws {
        let script = PlutusV2Script(data: Data("withdrawal script".utf8))
        let hash = try plutusScriptHash(script: .plutusV2Script(script))
        let network = MockChainContext().networkId
        let scriptAccount = try Address(stakingPart: .scriptHash(hash), network: network).toBytes()
        // A key credential whose hash sorts before the script's.
        let keyAccount = try Address(
            stakingPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x00, count: 28))),
            network: network
        ).toBytes()

        let builder = try builder()
        builder.withdrawals = Withdrawals([keyAccount: 1_000_000, scriptAccount: 2_000_000])
        try builder.addWithdrawalScript(.script(.plutusV2Script(script)), redeemer: try redeemer())
        _ = try await builder.build(changeAddress: try Address(from: .string(sender)))

        let redeemers = try redeemerList(builder)
        #expect(redeemers.first?.tag == .reward)
        #expect(redeemers.first?.index == 0)
    }

    @Test("The fee breakdown adds up to the fee the builder charges")
    func feeBreakdown() async throws {
        let builder = try builder()
        let body = try await builder.build(changeAddress: try Address(from: .string(sender)))
        let breakdown = try await builder.estimateFeeBreakdown()
        #expect(breakdown.total == body.fee)
        #expect(breakdown.sizeFee == breakdown.sizeBytes * breakdown.feePerByte)
        #expect(breakdown.executionFee == 0)
        #expect(breakdown.referenceScriptTiers.isEmpty)
    }

    @Test("Reference-script tiers are priced up by the multiplier")
    func referenceScriptTiers() async throws {
        let context = MockChainContext()
        let params = try await context.protocolParameters()
        let pricing = try #require(params.minFeeReferenceScripts)
        let range = try #require(pricing.range)
        let size = UInt64(range) * 2 + 10
        let (tiers, fee) = try await Utils.referenceScriptFeeTiers(context, scriptsSize: size)
        #expect(tiers.map(\.bytes) == [UInt64(range), UInt64(range), 10])
        #expect(tiers[1].pricePerByte == tiers[0].pricePerByte * (pricing.multiplier ?? 1))
        #expect(fee == UInt64(ceil(tiers.map(\.fee).reduce(0, +))))
        #expect(fee == (try await Utils.tieredReferenceScriptFee(context, scriptsSize: size)))
    }

    @Test("Evaluating execution units leaves the builder as it was")
    func evaluateLeavesBuilderAlone() async throws {
        let builder = try builder()
        #expect(builder.inputs.isEmpty)
        _ = try await builder.evaluateExecutionUnits(changeAddress: try Address(from: .string(sender)))
        #expect(builder.inputs.isEmpty)
    }
}

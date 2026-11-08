import BigInt
import Foundation
import Testing
import SwiftCardanoChain
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

/// Forwards to a `MockChainContext`, except for the tip and script
/// evaluation, which a test sets, as a lying provider would.
private final class ProviderContext: ChainContext, @unchecked Sendable {
    let inner: MockChainContext
    let type: SwiftCardanoChain.ContextType = .online
    var name: String = "ProviderContext"
    var tip = 2000
    var evaluation: [String: ExecutionUnits] = ["spend:0": ExecutionUnits(mem: 399_882, steps: 175_940_720)]

    init(_ inner: MockChainContext = MockChainContext()) { self.inner = inner }

    var networkId: NetworkId { inner.networkId }
    func protocolParameters() async throws -> ProtocolParameters { try await inner.protocolParameters() }
    func genesisParameters() async throws -> GenesisParameters { try await inner.genesisParameters() }
    func epoch() async throws -> Int { try await inner.epoch() }
    func era() async throws -> Era? { try await inner.era() }
    func lastBlockSlot() async throws -> Int { tip }
    func utxos(address: Address) async throws -> [UTxO] { try await inner.utxos(address: address) }
    func submitTxCBOR(cbor: Data) async throws -> String { try await inner.submitTxCBOR(cbor: cbor) }
    func evaluateTxCBOR(cbor: Data) async throws -> [String: ExecutionUnits] { evaluation }
    func stakeAddressInfo(address: Address) async throws -> [StakeAddressInfo] { try await inner.stakeAddressInfo(address: address) }
    func stakePools() async throws -> [PoolOperator] { try await inner.stakePools() }
}

private let senderBech32 = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

private func sender() throws -> Address { try Address(from: .string(senderBech32)) }

private func utxo(_ byte: UInt8, _ index: UInt16 = 0, coin: Int64, multiAsset: MultiAsset? = nil, script: ScriptType? = nil) throws -> UTxO {
    UTxO(
        input: TransactionInput(transactionId: try TransactionId(payload: Data(repeating: byte, count: 32)), index: index),
        output: TransactionOutput(
            address: try sender(),
            amount: multiAsset.map { Value(coin: coin, multiAsset: $0) } ?? Value(coin: coin),
            script: script
        )
    )
}

private func token(_ policyByte: UInt8, _ name: String, _ quantity: BigInt) throws -> MultiAsset {
    try MultiAsset(from: [Data(repeating: policyByte, count: 28).toHex: [name.toData.toHex: quantity]])
}

private func setParameter(_ context: MockChainContext, _ key: String, _ value: Decimal) async throws {
    try await context.editProtocolParameters { json in json[key] = .number(value) }
}

/// A Plutus V1 spend of a script UTxO with no execution units, so the
/// builder asks the context to evaluate it.
private func plutusSpend(_ context: any ChainContext) async throws -> TxBuilder {
    let builder = TxBuilder(context: context)
    let script = PlutusV1Script(data: Data("dummy test script".utf8))
    let scriptAddress = try Address(
        paymentPart: .scriptHash(try plutusScriptHash(script: .plutusV1Script(script))),
        stakingPart: .none,
        network: context.networkId
    )
    let datum = try Unit().toPlutusData()
    let scriptUtxo = UTxO(
        input: TransactionInput(transactionId: try TransactionId(payload: Data(repeating: 0x18, count: 32)), index: 0),
        output: TransactionOutput(address: scriptAddress, amount: Value(coin: 10_000_000), datumHash: try datum.hash())
    )
    try await builder
        .addInputAddress(.address(try sender()))
        .addScriptInput(scriptUtxo, script: .script(.plutusV1Script(script)), datum: .plutusData(datum), redeemer: Redeemer(data: try Unit().toPlutusData()))
        .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 5_000_000)))
    return builder
}

@Suite("Security regressions from the 2026-11-07 audit")
struct SecurityRegressionTests {

    // MARK: Fee cap and fee arithmetic

    @Test func inflatedFixedFeeIsRefusedByMaxFee() async throws {
        let context = MockChainContext()
        try await setParameter(context, "txFeeFixed", 1_000_000_000)
        context._utxos = [try utxo(0xaa, coin: 600_000_000), try utxo(0xab, coin: 600_000_000)]

        let capped = TxBuilder(context: context)
        try capped.addInputAddress(.address(try sender())).addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        await #expect(throws: CardanoTxBuilderError.self) { _ = try await capped.build(changeAddress: try sender()) }

        let uncapped = TxBuilder(context: context)
        uncapped.maxFee = nil
        try uncapped.addInputAddress(.address(try sender())).addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        let body = try await uncapped.build(changeAddress: try sender())
        #expect(body.fee > 1_000_000_000)
    }

    @Test func honestFeeIsWellBelowMaxFee() async throws {
        let context = MockChainContext()
        context._utxos = [try utxo(0xaa, coin: 600_000_000)]
        let builder = TxBuilder(context: context)
        try builder.addInputAddress(.address(try sender())).addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        let body = try await builder.build(changeAddress: try sender())
        #expect(body.fee < builder.maxFee!)
    }

    @Test func feeAboveInt64ThrowsInsteadOfTrapping() async throws {
        let context = MockChainContext()
        try await setParameter(context, "txFeeFixed", Decimal(string: "9223372036854775808")!)
        context._utxos = [try utxo(0xaa, coin: 2_000_000_000)]
        let builder = TxBuilder(context: context)
        builder.maxFee = nil
        try builder.addInputAddress(.address(try sender())).addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        await #expect(throws: CardanoTxBuilderError.self) { _ = try await builder.build(changeAddress: try sender()) }
    }

    @Test func feeTotalOverflowThrows() async throws {
        let context = MockChainContext()
        try await setParameter(context, "txFeeFixed", Decimal(string: "18446744073709551000")!)
        await #expect(throws: CardanoTxBuilderError.self) { _ = try await Utils.calculateFee(context, length: 300) }
    }

    @Test func minLovelaceOverflowThrows() async throws {
        let context = MockChainContext()
        try await setParameter(context, "utxoCostPerByte", 1_000_000_000_000_000_000)
        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await Utils.minLovelace(context, output: TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        }
    }

    @Test func selectorsThrowOnMaxFeeAboveInt64() async throws {
        let context = MockChainContext()
        try await setParameter(context, "txFeeFixed", Decimal(string: "9300000000000000000")!)
        let utxos = [try utxo(0xaa, coin: 2_000_000_000)]
        let outputs = [TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000))]
        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await LargestFirstSelector().select(utxos: utxos, outputs: outputs, context: context)
        }
        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await RandomImproveMultiAsset().select(utxos: utxos, outputs: outputs, context: context)
        }
    }

    // MARK: Coin selection

    @Test func manyDustUTxOsDoNotOverflowTheStack() async throws {
        let context = MockChainContext()
        var pool = [try utxo(0x01, coin: 100_000_000, multiAsset: try token(0x31, "TOK", 5))]
        for i in 0..<5_000 {
            pool.append(try utxo(UInt8(truncatingIfNeeded: i % 251 + 2), UInt16(i), coin: 1_500_000))
        }
        context._utxos = pool
        let builder = TxBuilder(context: context)
        try builder.addInputAddress(.address(try sender()))
            .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 5_000_000, multiAsset: try token(0x31, "TOK", 5))))
        // Either outcome is fine; the process must not crash.
        _ = try? await builder.build(changeAddress: try sender())
    }

    @Test func tokenQuantityAboveInt64DoesNotTrapSelection() async throws {
        let context = MockChainContext()
        context._utxos = [
            try utxo(0x01, coin: 5_000_000, multiAsset: try token(0x31, "X", 100)),
            try utxo(0x02, coin: 2_000_000, multiAsset: try token(0x31, "X", BigInt(1) << 63)),
        ]
        let builder = TxBuilder(context: context)
        try builder.addInputAddress(.address(try sender()))
            .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 2_000_000, multiAsset: try token(0x31, "X", 60))))
        _ = try? await builder.build(changeAddress: try sender())
    }

    // MARK: Provider tip, execution units, rewards, tier loop

    @Test func tipNearIntMaxThrows() async throws {
        let context = ProviderContext()
        context.tip = Int.max
        let builder = TxBuilder(context: context)
        try builder.addInputAddress(.address(try sender())).addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await builder.build(changeAddress: try sender(), autoTtlOffset: 10_000)
        }
        context.tip = 2000
        let ok = TxBuilder(context: context)
        try ok.addInputAddress(.address(try sender())).addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        _ = try await ok.build(changeAddress: try sender(), autoTtlOffset: 10_000)
        #expect(ok.ttl == 12_000)
    }

    @Test(arguments: [Int64(8_000_000_000_000_000_000), Int64.max])
    func hugeEvaluatedUnitsThrow(mem: Int64) async throws {
        let context = ProviderContext()
        context.evaluation = ["spend:0": ExecutionUnits(mem: mem, steps: 1)]
        let builder = try await plutusSpend(context)
        await #expect(throws: CardanoTxBuilderError.self) { _ = try await builder.build(changeAddress: try sender()) }
    }

    @Test func honestEvaluatedUnitsStillBuild() async throws {
        let builder = try await plutusSpend(ProviderContext())
        _ = try await builder.build(changeAddress: try sender())
    }

    @Test func rewardSumOverflowThrows() async throws {
        let context = MockChainContext()
        let stake = try Address(stakingPart: .verificationKeyHash(try stakeVerificationKey!.hash()), network: .testnet)
        context._stakeAddressInfo = [
            StakeAddressInfo(address: try stake.toBech32(), rewardAccountBalance: Int64.max),
            StakeAddressInfo(address: try stake.toBech32(), rewardAccountBalance: 1),
        ]
        let builder = TxBuilder(context: context)
        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await builder.transactions.withdrawRewards(from: stakeVerificationKey!, feePaymentAddress: try sender())
        }
    }

    @Test func tinyReferenceScriptTierStrideIsRefused() async throws {
        let context = MockChainContext()
        try await context.editProtocolParameters { json in
            json["minFeeReferenceScripts"] = .object(["base": .number(44), "multiplier": .number(Decimal(string: "1.2")!), "range": .number(1)])
        }
        let start = Date()
        await #expect(throws: CardanoTxBuilderError.self) { _ = try await Utils.referenceScriptFeeTiers(context, scriptsSize: 2_000) }
        #expect(Date().timeIntervalSince(start) < 5)
        // Honest tiers still work.
        let honest = MockChainContext()
        #expect(try await Utils.referenceScriptFeeTiers(honest, scriptsSize: 204_800).tiers.count == 8)
    }

    // MARK: Reference scripts on spent inputs

    @Test func referenceScriptOnSpentInputIsPriced() async throws {
        let script = ScriptType.plutusV2Script(PlutusV2Script(data: Data(repeating: 0x4e, count: 2_000)))
        func fee(_ carried: ScriptType?) async throws -> Int {
            let context = MockChainContext()
            context._utxos = []
            let builder = TxBuilder(context: context)
            try builder.addInput(try utxo(0xaa, coin: 50_000_000, script: carried))
                .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 5_000_000)))
            return Int(try await builder.build(changeAddress: try sender()).fee)
        }
        let without = try await fee(nil)
        let with = try await fee(script)
        let tiered = try await Utils.tieredReferenceScriptFee(MockChainContext(), scriptsSize: 2_000)
        #expect(with - without >= Int(tiered))
    }

    // MARK: Correctness fixes

    @Test func nofKNativeScriptSignersAreCounted() async throws {
        let keyHash = try paymentVerificationKey!.hash()
        func fee(_ script: NativeScript) async throws -> Int {
            let context = MockChainContext()
            context._utxos = [try utxo(0xaa, coin: 50_000_000)]
            let builder = TxBuilder(context: context)
            builder.nativeScripts = [script]
            try builder.addInputAddress(.address(try sender()))
                .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 5_000_000)))
            _ = try await builder.build(changeAddress: try sender())
            return Int(try await builder.estimateFeeBreakdown().sizeBytes)
        }
        let other = try VerificationKeyHash(payload: Data(repeating: 0x77, count: 28))
        let plain = try await fee(.scriptAny(ScriptAny(scripts: [.scriptPubkey(ScriptPubkey(keyHash: other))])))
        let nofk = try await fee(.scriptNofK(ScriptNofK(required: 1, scripts: [.scriptPubkey(ScriptPubkey(keyHash: other))])))
        // The same key under scriptNofK must add the same placeholder witness
        // as under scriptAny; the scripts differ by a few bytes only.
        #expect(abs(plain - nofk) < 20)
        _ = keyHash
        // And the key is part of the required set, so the fee pays for its witness.
        let context = MockChainContext()
        context._utxos = [try utxo(0xaa, coin: 50_000_000)]
        let builder = TxBuilder(context: context)
        builder.nativeScripts = [.scriptNofK(ScriptNofK(required: 1, scripts: [.scriptPubkey(ScriptPubkey(keyHash: keyHash))]))]
        try builder.addInputAddress(.address(try sender()))
            .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 5_000_000)))
        _ = try await builder.build(changeAddress: try sender())
        let one = MockChainContext(); one._utxos = [try utxo(0xaa, coin: 50_000_000)]
        let none = TxBuilder(context: one)
        try none.addInputAddress(.address(try sender()))
            .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 5_000_000)))
        _ = try await none.build(changeAddress: try sender())
        // Same payment key signs both, so the NofK build needs no more witnesses than the plain one,
        // but it must not need fewer than the key it names.
        #expect(try await builder.estimateFeeBreakdown().sizeBytes >= (try await none.estimateFeeBreakdown().sizeBytes))
    }

    @Test func autoCollateralSkipsExcludedInputs() async throws {
        let context = MockChainContext()
        let reserved = try utxo(0xee, coin: 50_000_000)
        context._utxos = [try utxo(0xaa, coin: 3_000_000), reserved]
        let builder = try await plutusSpend(context)
        builder.excludedInputs = [reserved]
        if let body = try? await builder.build(changeAddress: try sender()) {
            let collateral = body.collateral?.asList ?? []
            #expect(!collateral.contains(reserved.input))
        }
        #expect(!builder.collaterals.contains(reserved))
    }

    @Test func callerCollateralInExcludedInputsIsRejected() async throws {
        let context = MockChainContext()
        let reserved = try utxo(0xee, coin: 50_000_000)
        context._utxos = [try utxo(0xaa, coin: 30_000_000)]
        let builder = try await plutusSpend(context)
        builder.excludedInputs = [reserved]
        builder.collaterals = [reserved]
        await #expect(throws: CardanoTxBuilderError.self) { _ = try await builder.build(changeAddress: try sender()) }
    }

    @Test func mergeChangeNeverReturnsAnOutputBelowMinAda() async throws {
        let context = MockChainContext()
        context._utxos = []
        let builder = TxBuilder(context: context)
        try builder.addInput(try utxo(0xaa, coin: 1_200_000, multiAsset: try token(0x42, String(repeating: "n", count: 32), 1)))
            .addOutput(TransactionOutput(address: try sender(), amount: Value(coin: 1_000_000)))
        do {
            let body = try await builder.build(changeAddress: try sender(), mergeChange: true)
            for output in body.outputs {
                let minimum = try await Utils.minLovelacePostAlonzo(output, context)
                #expect(output.amount.coin >= BigInt(minimum))
            }
        } catch is CardanoTxBuilderError {
            // Refusing is the expected outcome for these inputs.
        }
    }
}

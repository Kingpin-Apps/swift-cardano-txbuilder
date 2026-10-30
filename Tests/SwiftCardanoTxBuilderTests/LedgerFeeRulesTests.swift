import BigInt
import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
@testable import SwiftCardanoTxBuilder

/// The fee and deposit rules as the ledger applies them.
@Suite("Ledger fee rules")
struct LedgerFeeRulesTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    @Test("Script execution is charged as the ledger's txscriptfee: one rounding of the exact sum")
    func executionFeeRoundsOnce() async throws {
        // 1 memory unit at 0.0577 and 1 step at 0.0000721 cost 0.0577721
        // together: 1 lovelace, though each rounded up alone is 1.
        let breakdown = try await Utils.feeBreakdown(MockChainContext(), length: 0, execSteps: 1, maxMemUnit: 1)
        #expect(breakdown.memoryFee == 1)
        #expect(breakdown.stepsFee == 1)
        #expect(breakdown.executionFee == 1)
        #expect(breakdown.total == breakdown.fixedFee + 1)

        // Exact amounts need no rounding: 57,700 + 72,100.
        let exact = try await Utils.feeBreakdown(
            MockChainContext(), length: 0, execSteps: 1_000_000_000, maxMemUnit: 1_000_000)
        #expect(exact.executionFee == 129_800)
        #expect(exact.executionFee == exact.memoryFee + exact.stepsFee)
    }

    @Test("Two Conway registrations with the same deposit both take it from the inputs")
    func repeatedDepositsAreEachCharged() async throws {
        var sequence: [Int] = [0, 0, 0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: { sequence.isEmpty ? 0 : sequence.removeFirst() })
        let context = MockChainContext()
        let builder = TxBuilder(context: context, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        try builder.addInputAddress(.string(sender)).addOutput(
            TransactionOutput(address: senderAddress, amount: Value(coin: 500_000))
        )
        builder.certificates = try [0x5A, 0x5B].map { byte in
            .register(try Register(
                stakeCredential: StakeCredential(
                    credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28)))),
                coin: 2_000_000))
        }

        let body = try await builder.build(changeAddress: senderAddress)
        let available = try await context.utxos(address: senderAddress)
        let inputs = body.inputs.asArray.compactMap { input in available.first { $0.input == input } }
        #expect(inputs.count == body.inputs.asArray.count)
        let consumed = inputs.reduce(BigInt(0)) { $0 + $1.output.amount.coin }
        let produced = body.outputs.reduce(BigInt(0)) { $0 + $1.amount.coin }
        #expect(consumed == produced + BigInt(body.fee) + 4_000_000)
    }
}

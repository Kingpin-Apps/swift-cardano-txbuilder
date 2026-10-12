import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
@testable import SwiftCardanoTxBuilder

@Suite("Reference inputs")
struct ReferenceInputTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    func build(reading reference: UTxO?) async throws -> TransactionBody {
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: { sequence.removeFirst() })
        let builder = TxBuilder(context: MockChainContext(), utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        try builder.addInputAddress(.string(sender)).addOutput(
            TransactionOutput(address: senderAddress, amount: Value(coin: 500_000))
        )
        if let reference {
            builder.addReferenceInput(reference)
            builder.addReferenceInput(reference)
        }
        return try await builder.build(changeAddress: senderAddress)
    }

    func reference(script: ScriptType?) throws -> UTxO {
        var output = TransactionOutput(address: try Address(from: .string(sender)), amount: Value(coin: 2_000_000))
        output.script = script
        output.postAlonzo = true
        return UTxO(input: TransactionInput(transactionId: TransactionId(payload: Data(repeating: 9, count: 32)), index: 3), output: output)
    }

    @Test("A reference input is read, once, and not spent")
    func read() async throws {
        let reference = try reference(script: nil)
        let body = try await build(reading: reference)
        #expect(body.referenceInputs?.asList == [reference.input])
        #expect(!body.inputs.asArray.contains(reference.input))
        let plain = try await build(reading: nil)
        #expect(plain.referenceInputs == nil)
    }

    @Test("A reference script it carries is priced into the fee")
    func scriptFee() async throws {
        let script = ScriptType.plutusV2Script(PlutusV2Script(data: Data(repeating: 0x4e, count: 2_000)))
        let withScript = try await build(reading: try reference(script: script))
        let without = try await build(reading: try reference(script: nil))
        #expect(withScript.fee > without.fee)
    }
}

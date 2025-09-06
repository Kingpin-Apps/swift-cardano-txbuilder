import Foundation
import SwiftCardanoCore
import SwiftCardanoTxBuilder
import Testing

@Suite("Types Tests")
struct TypesTests {
    let testAddressString =
        "addr_test1xznnmfk43w5cag3m7e9nnfe0wcsg5lx8afv4u9utjk3zxvzrkm6eqegp9gcz0q44d3t5j0j7qcuvxcax7d3fsg23x33q8uptcp"
    
    @Test("ScriptOrUTxO conversions and type checking")
    func testScriptOrUTxO() async throws {
        // Test script case
        let mockScript = PlutusV2Script(data: Data([0x01, 0x02, 0x03]))
        let scriptCase = ScriptOrUTxO.script(.plutusV2Script(mockScript))

        #expect(scriptCase.asScript != nil)
        #expect(scriptCase.asUTxO == nil)
        if case let .plutusV2Script(script) = scriptCase.asScript {
            #expect(script == mockScript)
        } else {
            Issue.record("Script case is not of the expected type")
        }

        // Test UTxO case
        let mockTransactionInput = TransactionInput(
            transactionId: TransactionId(
                payload: Data([0x01, 0x02, 0x03])),
            index: 0
        )
        let mockTransactionOutput = try TransactionOutput(
            address: Address(
                from: .string(testAddressString)
            ),
            amount: Value(coin: 1_000_000)
        )
        let mockUTxO = UTxO(input: mockTransactionInput, output: mockTransactionOutput)
        let utxoCase = ScriptOrUTxO.utxo(mockUTxO)

        #expect(utxoCase.asScript == nil)
        #expect(utxoCase.asUTxO != nil)
        #expect(utxoCase.asUTxO == mockUTxO)
    }

    @Test("UTxOOrTransactionInput conversions and type checking")
    func testUTxOOrTransactionInput() async throws {
        // Test UTxO case
        let mockTransactionInput = TransactionInput(
            transactionId: TransactionId(
                payload: Data([0x01, 0x02, 0x03])),
            index: 0
        )
        let mockTransactionOutput = try TransactionOutput(
            address: Address(
                from: .string(testAddressString)
            ),
            amount: Value(coin: 1_000_000)
        )
        let mockUTxO = UTxO(input: mockTransactionInput, output: mockTransactionOutput)

        let utxoCase = UTxOOrTransactionInput.utxo(mockUTxO)
        #expect(utxoCase.asUTxO != nil)
        #expect(utxoCase.asInput == nil)
        #expect(utxoCase.asUTxO == mockUTxO)

        // Test TransactionInput case
        let inputCase = UTxOOrTransactionInput.input(mockTransactionInput)
        #expect(inputCase.asUTxO == nil)
        #expect(inputCase.asInput != nil)
        #expect(inputCase.asInput == mockTransactionInput)
    }

    @Test("AddressOrString conversions and type checking")
    func testAddressOrString() async throws {
        
        let address = try Address(from: .string(testAddressString))

        // Test address case
        let addressCase = AddressOrString.address(address)
        #expect(addressCase.asAddress != nil)
        #expect(try addressCase.asString == address.toBech32())
        #expect(addressCase.asAddress == address)

        // Test string case
        let stringCase = AddressOrString.string(testAddressString)
        #expect(stringCase.asAddress != nil)
        #expect(stringCase.asString == testAddressString)
        #expect(stringCase.asAddress == address)
    }
}

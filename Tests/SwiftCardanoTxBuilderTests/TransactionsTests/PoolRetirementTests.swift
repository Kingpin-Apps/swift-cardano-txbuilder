import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Pool Retirement")
struct PoolRetirementTests {
    
    @Test func testPoolRetirement() async throws {
        // Arrange
        let chainContext = MockChainContext()
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let pool = poolOperator
        let retirementEpoch: EpochNumber = 400
        let txBuilder = TxBuilder(context: chainContext)
        
        // Act: Create pool retirement transaction
        let tx = try await txBuilder.transactions.poolRetirement(
            poolOperator: pool,
            epoch: retirementEpoch,
            feePaymentAddress: feePaymentAddress
        )
        
        // Assert
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasPoolRetirement = body.certificates!.asList.contains { cert in
            if case .poolRetirement = cert {
                return true
            }
            return false
        }
        #expect(hasPoolRetirement, "Should have a PoolRetirement certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")

        // Value conservation: a pool retirement certificate does NOT refund the
        // stake-pool deposit in this transaction (the ledger returns it to the
        // reward account at the retirement epoch). Consumed (inputs) must equal
        // produced (outputs + fee); a regression that credits stakePoolDeposit
        // would make the outputs exceed the inputs by the deposit and the ledger
        // would reject the tx with ValueNotConservedUTxO.
        let availableUtxos = try await chainContext.utxos(address: feePaymentAddress)
        var inputTotal: Int64 = 0
        for input in body.inputs.asArray {
            if let utxo = availableUtxos.first(where: { $0.input == input }) {
                inputTotal += utxo.output.amount.coin
            }
        }
        let outputTotal = body.outputs.reduce(Int64(0)) { $0 + $1.amount.coin }
        #expect(
            inputTotal == outputTotal + Int64(body.fee),
            "Pool retirement must conserve value (no deposit refund): inputs \(inputTotal) != outputs \(outputTotal) + fee \(body.fee)"
        )
    }
}

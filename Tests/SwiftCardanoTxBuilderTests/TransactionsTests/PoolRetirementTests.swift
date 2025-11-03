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
        let retirementEpoch = 400
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
    }
}

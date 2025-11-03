import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Pool Registration")
struct PoolRegistrationTests {
    
    @Test func testPoolRegistration() async throws {
        // Arrange
        let chainContext = MockChainContext()
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let params = poolParams
        let txBuilder = TxBuilder(context: chainContext)
        
        // Act: Create pool registration transaction
        let tx = try await txBuilder.transactions.poolRegistration(
            poolParams: params,
            feePaymentAddress: feePaymentAddress
        )
        
        // Assert
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasPoolRegistration = body.certificates!.asList.contains { cert in
            if case .poolRegistration = cert {
                return true
            }
            return false
        }
        #expect(hasPoolRegistration, "Should have a PoolRegistration certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

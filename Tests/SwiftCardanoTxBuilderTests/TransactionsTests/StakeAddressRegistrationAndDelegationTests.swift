import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Stake Address Registration And Delegation")
struct StakeAddressRegistrationAndDelegationTests {
    
    @Test func testStakeAddressRegistrationAndDelegation() async throws {
        // Arrange: Setup mock chain context
        let chainContext = MockChainContext()
        
        guard let stakeVK = stakeVerificationKey else {
            Issue.record("Failed to load stake verification key")
            return
        }
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        // Mock: Stake address is NOT registered
        chainContext._stakeAddressInfo = []
        
        let pool = poolOperator
        let txBuilder = TxBuilder(context: chainContext)
        
        // Act: Create stake address registration and delegation transaction
        let tx = try await txBuilder.transactions.stakeAddressRegistrationAndDelegation(
            stakeVerificationKey: stakeVK,
            poolOperator: pool,
            feePaymentAddress: feePaymentAddress
        )
        
        // Assert
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        #expect(body.certificates!.count > 0, "Should have at least one certificate")
        
        let hasStakeRegisterDelegate = body.certificates!.asList.contains { cert in
            if case .stakeRegisterDelegate = cert {
                return true
            }
            return false
        }
        #expect(hasStakeRegisterDelegate, "Should have a StakeRegisterDelegate certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

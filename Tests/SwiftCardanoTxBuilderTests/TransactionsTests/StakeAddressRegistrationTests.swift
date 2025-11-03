import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Stake Address Registration")
struct StakeAddressRegistrationTests {
    
    @Test func testStakeAddressRegistration() async throws {
        // Arrange: Setup mock chain context
        let chainContext = MockChainContext()
        
        // Load keys from fixtures
        guard let stakeVK = stakeVerificationKey else {
            Issue.record("Failed to load stake verification key")
            return
        }
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        // Create fee payment address from payment verification key
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        // Mock: Stake address is NOT registered (empty stakeAddressInfo)
        chainContext._stakeAddressInfo = []
        
        // Create a TxBuilder instance
        let txBuilder = TxBuilder(context: chainContext)
        
        // Act: Create stake address registration transaction
        let tx = try await txBuilder.transactions.stakeAddressRegistration(
            stakeVerificationKey: stakeVK,
            feePaymentAddress: feePaymentAddress
        )
        
        // Assert: Verify transaction structure
        let body = tx.transactionBody
        
        // 1. Should have inputs (for fee payment)
        #expect(body.inputs.count > 0, "Transaction should have at least one input for fee payment")
        
        // 2. Should have certificates with StakeRegistration
        #expect(body.certificates != nil, "Transaction should have certificates")
        #expect(body.certificates!.count > 0, "Should have at least one certificate")
        
        // Check that at least one certificate is a StakeRegistration
        let hasStakeRegistration = body.certificates!.asList.contains { cert in
            if case .stakeRegistration = cert {
                return true
            }
            return false
        }
        #expect(hasStakeRegistration, "Should have a StakeRegistration certificate")
        
        // 3. Fee should be calculated
        #expect(body.fee > 0, "Transaction fee should be calculated and non-zero")
    }
}

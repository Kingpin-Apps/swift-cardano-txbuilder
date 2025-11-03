import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Stake Delegation")
struct StakeDelegationTests {
    
    @Test func testStakeDelegation() async throws {
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
        
        // Create fee payment address
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        // Create stake address
        let stakeAddress = try Address(
            stakingPart: .verificationKeyHash(try stakeVK.hash()),
            network: chainContext.networkId
        )
        
        // Mock: Stake address IS registered
        chainContext._stakeAddressInfo = [
            StakeAddressInfo(
                active: true,
                activeEpoch: 100,
                address: try stakeAddress.toBech32(),
                rewardAccountBalance: 0
            )
        ]
        
        // Use poolOperator fixture
        let pool = poolOperator
        
        // Create a TxBuilder instance
        let txBuilder = TxBuilder(context: chainContext)
        
        // Act: Create stake delegation transaction
        let tx = try await txBuilder.transactions.stakeDelegation(
            stakeVerificationKey: stakeVK,
            poolOperator: pool,
            feePaymentAddress: feePaymentAddress
        )
        
        // Assert: Verify transaction structure
        let body = tx.transactionBody
        
        // 1. Should have inputs
        #expect(body.inputs.count > 0, "Transaction should have at least one input for fee payment")
        
        // 2. Should have certificates with StakeDelegation
        #expect(body.certificates != nil, "Transaction should have certificates")
        #expect(body.certificates!.count > 0, "Should have at least one certificate")
        
        let hasStakeDelegation = body.certificates!.asList.contains { cert in
            if case .stakeDelegation = cert {
                return true
            }
            return false
        }
        #expect(hasStakeDelegation, "Should have a StakeDelegation certificate")
        
        // 3. Fee should be calculated
        #expect(body.fee > 0, "Transaction fee should be calculated and non-zero")
    }
}

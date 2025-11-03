import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Stake Address Registration Delegation And Vote Delegation")
struct StakeAddressRegistrationDelegationAndVoteDelegationTests {
    
    @Test func testStakeAddressRegistrationStakeDelegationAndVoteDelegation() async throws {
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
        
        chainContext._stakeAddressInfo = []
        
        let pool = poolOperator
        let dRep = drep
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.stakeAddressRegistrationStakeDelegationAndVoteDelegation(
            stakeVerificationKey: stakeVK,
            poolOperator: pool,
            drep: dRep,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasStakeVoteRegisterDelegate = body.certificates!.asList.contains { cert in
            if case .stakeVoteRegisterDelegate = cert {
                return true
            }
            return false
        }
        #expect(hasStakeVoteRegisterDelegate, "Should have a StakeVoteRegisterDelegate certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

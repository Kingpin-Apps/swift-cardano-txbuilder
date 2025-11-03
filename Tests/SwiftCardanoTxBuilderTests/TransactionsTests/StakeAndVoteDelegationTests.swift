import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Stake And Vote Delegation")
struct StakeAndVoteDelegationTests {
    
    @Test func testStakeAndVoteDelegation() async throws {
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
        
        let pool = poolOperator
        let dRep = drep
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.stakeAndVoteDelegation(
            stakeVerificationKey: stakeVK,
            poolOperator: pool,
            drep: dRep,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasStakeVoteDelegate = body.certificates!.asList.contains { cert in
            if case .stakeVoteDelegate = cert {
                return true
            }
            return false
        }
        #expect(hasStakeVoteDelegate, "Should have a StakeVoteDelegate certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

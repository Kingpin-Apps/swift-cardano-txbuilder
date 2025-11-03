import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Unregister")
struct UnregisterTests {
    
    @Test func testUnregister() async throws {
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
        
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.unregister(
            stakeVerificationKey: stakeVK,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasUnregister = body.certificates!.asList.contains { cert in
            if case .unregister = cert {
                return true
            }
            return false
        }
        #expect(hasUnregister, "Should have an Unregister certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

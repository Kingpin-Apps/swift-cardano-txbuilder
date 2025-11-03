import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Register")
struct RegisterTests {
    
    @Test func testRegister() async throws {
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
        
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.register(
            stakeVerificationKey: stakeVK,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasRegister = body.certificates!.asList.contains { cert in
            if case .register = cert {
                return true
            }
            return false
        }
        #expect(hasRegister, "Should have a Register certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Unregister DRep")
struct UnregisterDRepTests {
    
    @Test func testUnregisterDRep() async throws {
        let chainContext = MockChainContext()
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let drepCred = drepCredential
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.unregisterDRep(
            drepCredential: drepCred,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasUnRegisterDRep = body.certificates!.asList.contains { cert in
            if case .unRegisterDRep = cert {
                return true
            }
            return false
        }
        #expect(hasUnRegisterDRep, "Should have an UnregisterDRep certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

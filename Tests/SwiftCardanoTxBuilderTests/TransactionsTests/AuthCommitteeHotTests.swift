import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Auth Committee Hot")
struct AuthCommitteeHotTests {
    
    @Test func testAuthCommitteeHot() async throws {
        let chainContext = MockChainContext()
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let coldCred = committeeColdCredential
        let hotCred = committeeHotCredential
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.authCommitteeHot(
            committeeColdCredential: coldCred,
            committeeHotCredential: hotCred,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasAuthCommitteeHot = body.certificates!.asList.contains { cert in
            if case .authCommitteeHot = cert {
                return true
            }
            return false
        }
        #expect(hasAuthCommitteeHot, "Should have an AuthCommitteeHot certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

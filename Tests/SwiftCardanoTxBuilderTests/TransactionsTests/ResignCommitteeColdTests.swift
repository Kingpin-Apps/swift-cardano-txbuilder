import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Resign Committee Cold")
struct ResignCommitteeColdTests {
    
    @Test func testResignCommitteeCold() async throws {
        let chainContext = MockChainContext()
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let coldCred = committeeColdCredential
        let gov_anchor = anchor
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.resignCommitteeCold(
            committeeColdCredential: coldCred,
            anchor: gov_anchor,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasResignCommitteeCold = body.certificates!.asList.contains { cert in
            if case .resignCommitteeCold = cert {
                return true
            }
            return false
        }
        #expect(hasResignCommitteeCold, "Should have a ResignCommitteeCold certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

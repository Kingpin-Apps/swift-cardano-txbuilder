import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Register DRep")
struct RegisterDRepTests {
    
    @Test func testRegisterDRep() async throws {
        // Arrange
        let chainContext = MockChainContext()
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let drepCred = drepCredential
        let gov_anchor = anchor
        let txBuilder = TxBuilder(context: chainContext)
        
        // Act: Create DRep registration transaction
        let tx = try await txBuilder.transactions.registerDRep(
            drepCredential: drepCred,
            anchor: gov_anchor,
            feePaymentAddress: feePaymentAddress
        )
        
        // Assert
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasRegisterDRep = body.certificates!.asList.contains { cert in
            if case .registerDRep = cert {
                return true
            }
            return false
        }
        #expect(hasRegisterDRep, "Should have a RegisterDRep certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

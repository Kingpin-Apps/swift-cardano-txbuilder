import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Witness")
struct WitnessTests {
    
    @Test func testWitness() async throws {
        // Arrange: Create a transaction to witness
        let chainContext = MockChainContext()
        
        guard paymentVerificationKey != nil else {
            Issue.record("Failed to load payment verification key")
            return
        }
        
        guard let paymentSK = paymentSigningKey else {
            Issue.record("Failed to load payment signing key")
            return
        }
        
        let feePaymentAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        // Create a simple transaction
        let txBuilder = TxBuilder(context: chainContext)
        let receiver = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        
        txBuilder.addInputAddress(.address(feePaymentAddress))
        try txBuilder.addOutput(TransactionOutput(
            address: receiver,
            amount: Value(coin: 1_000_000)
        ))
        
        let txBody = try await txBuilder.build(changeAddress: feePaymentAddress)
        let tx = Transaction(
            transactionBody: txBody,
            transactionWitnessSet: TransactionWitnessSet(),
            auxiliaryData: nil
        )
        
        // Act: Create witnesses for the transaction
        let witnesses = try txBuilder.transactions.witness(
            transaction: tx,
            keys: [.signingKey(paymentSK)]
        )
        
        // Assert: Witnesses should be created
        #expect(witnesses.count > 0, "Should have at least one witness")
        
        let witness = witnesses[0]
        #expect(witness.vkey.payload.count > 0, "Witness should have a verification key")
        #expect(witness.signature.count == 64, "Signature should be 64 bytes (ed25519)")
    }
}

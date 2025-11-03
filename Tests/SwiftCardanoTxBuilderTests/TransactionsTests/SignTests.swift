import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Sign")
struct SignTests {
    
    @Test func testSign() async throws {
        // Arrange: Create an unsigned transaction
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
        
        // Create a simple unsigned transaction
        let txBuilder = TxBuilder(context: chainContext)
        let receiver = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        
        txBuilder.addInputAddress(.address(feePaymentAddress))
        try txBuilder.addOutput(TransactionOutput(
            address: receiver,
            amount: Value(coin: 1_000_000)
        ))
        
        let txBody = try await txBuilder.build(changeAddress: feePaymentAddress)
        let unsignedTx = Transaction(
            transactionBody: txBody,
            transactionWitnessSet: TransactionWitnessSet(),
            auxiliaryData: nil
        )
        
        // Act: Sign the transaction
        let signedTx = try await txBuilder.transactions.sign(
            transaction: unsignedTx,
            keys: [.signingKey(paymentSK)]
        )
        
        // Assert: Transaction should now have witnesses
        #expect(signedTx.transactionWitnessSet.vkeyWitnesses != nil, "Signed transaction should have vkey witnesses")
        let witnesses = signedTx.transactionWitnessSet.vkeyWitnesses!.asList
        #expect(witnesses.count > 0, "Should have at least one witness")
        
        // Transaction body should remain the same
        #expect(signedTx.transactionBody.fee == unsignedTx.transactionBody.fee, "Transaction body fee should be unchanged")
        #expect(signedTx.transactionBody.inputs.count == unsignedTx.transactionBody.inputs.count, "Transaction inputs should be unchanged")
    }
}

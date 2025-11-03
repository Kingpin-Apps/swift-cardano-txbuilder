import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Test Vote Register And Delegation")
struct VoteRegisterAndDelegationTests {
    
    @Test func testVoteRegisterAndDelegation() async throws {
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
        
        // Create a UTxO with sufficient funds for dRepDeposit (500M lovelace) + fees
        let txIn = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0x99, count: 32)),
            index: 0
        )
        let txOut = TransactionOutput(
            address: feePaymentAddress,
            amount: Value(coin: 600_000_000) // 600 ADA to cover 500M deposit + fees
        )
        chainContext._utxos = [UTxO(input: txIn, output: txOut)]
        
        let dRep = drep
        let txBuilder = TxBuilder(context: chainContext)
        
        let tx = try await txBuilder.transactions.voteRegisterAndDelegation(
            stakeVerificationKey: stakeVK,
            drep: dRep,
            feePaymentAddress: feePaymentAddress
        )
        
        let body = tx.transactionBody
        #expect(body.inputs.count > 0, "Should have inputs for fee payment")
        #expect(body.certificates != nil, "Should have certificates")
        
        let hasVoteRegisterDelegate = body.certificates!.asList.contains { cert in
            if case .voteRegisterDelegate = cert {
                return true
            }
            return false
        }
        #expect(hasVoteRegisterDelegate, "Should have a VoteRegisterDelegate certificate")
        #expect(body.fee > 0, "Transaction fee should be non-zero")
    }
}

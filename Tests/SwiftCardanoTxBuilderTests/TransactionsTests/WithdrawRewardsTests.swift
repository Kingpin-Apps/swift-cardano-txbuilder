import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder


@Suite("Test Withdraw Rewards")
struct WithdrawRewardsTests {
    
    @Test func testWithdrawRewards() async throws {
        // Arrange: Setup mock chain context with rewards
        let chainContext = MockChainContext()
        
        // Load stake verification key from fixtures
        guard let stakeVK = stakeVerificationKey else {
            Issue.record("Failed to load stake verification key")
            return
        }
        
        // Create stake address from the verification key
        let stakeAddress = try Address(
            stakingPart: .verificationKeyHash(try stakeVK.hash()),
            network: chainContext.networkId
        )
        
        // Mock rewards of 5,000,000 lovelace for this stake address
        let rewardBalance = 5_000_000
        chainContext._stakeAddressInfo = [
            StakeAddressInfo(
                address: try stakeAddress.toBech32(),
                rewardAccountBalance: rewardBalance
            )
        ]
        
        // Setup fee payment address (sender)
        let sender = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        // Create a TxBuilder instance
        let txBuilder = TxBuilder(context: chainContext)
        
        // Test Scenario A: Withdraw to explicit receiver address
        let receiver = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        
        let txWithReceiver = try await txBuilder.transactions.withdrawRewards(
            from: stakeVK,
            to: receiver,
            feePaymentAddress: sender
        )
        
        // Verify transaction structure
        let bodyA = txWithReceiver.transactionBody
        
        // 1. Should have inputs (for fee payment)
        #expect(bodyA.inputs.count > 0, "Transaction should have at least one input for fee payment")
        
        // 2. Should have withdrawals with correct stake address and amount
        #expect(bodyA.withdrawals != nil, "Transaction should have withdrawals")
        #expect(bodyA.withdrawals!.data.count == 1, "Should have exactly one withdrawal")
        let withdrawalPair = bodyA.withdrawals!.data.elements.first!
        #expect(Int(withdrawalPair.value) == rewardBalance, "Withdrawal amount should match reward balance")
        
        // 3. Should have output to receiver with the reward amount
        let receiverOutputs = bodyA.outputs.filter { $0.address == receiver }
        #expect(!receiverOutputs.isEmpty, "Should have output to receiver address")
        if let receiverOutput = receiverOutputs.first {
            #expect(receiverOutput.amount.coin == rewardBalance, "Receiver output should have the full reward amount")
        }
        
        // 4. Fee should be calculated
        #expect(bodyA.fee > 0, "Transaction fee should be calculated and non-zero")
        
        // Test Scenario B: Withdraw without explicit receiver (merge with change)
        let txBuilder2 = TxBuilder(context: chainContext)
        
        let txWithoutReceiver = try await txBuilder2.transactions.withdrawRewards(
            from: stakeVK,
            to: nil,
            feePaymentAddress: sender
        )
        
        let bodyB = txWithoutReceiver.transactionBody
        
        // 1. Should have inputs
        #expect(bodyB.inputs.count > 0, "Transaction should have at least one input for fee payment")
        
        // 2. Should have withdrawals
        #expect(bodyB.withdrawals != nil, "Transaction should have withdrawals")
        #expect(bodyB.withdrawals!.data.count == 1, "Should have exactly one withdrawal")
        let withdrawalPairB = bodyB.withdrawals!.data.elements.first!
        #expect(Int(withdrawalPairB.value) == rewardBalance, "Withdrawal amount should match reward balance")
        
        // 3. Should NOT have a separate output to receiver (rewards merged with change to sender)
        let receiverOutputsB = bodyB.outputs.filter { $0.address == receiver }
        #expect(receiverOutputsB.isEmpty, "Should not have separate output to receiver when toAddress is nil")
        
        // 4. Should have change output to sender (with rewards merged)
        let senderOutputs = bodyB.outputs.filter { $0.address == sender }
        #expect(!senderOutputs.isEmpty, "Should have change output to fee payment address")
        
        // 5. Fee should be calculated
        #expect(bodyB.fee > 0, "Transaction fee should be calculated and non-zero")
    }
}

import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Create a transaction that withdraws rewards from a stake address.
    /// - Parameters:
    ///   - stakeVerificationKey: The stake verification key associated with the stake address
    ///   - toAddress: The address to send the withdrawn rewards to. If `nil`, rewards will be sent to the stake `feePaymentAddress`.
    ///   - feePaymentAddress: The address to pay the transaction fee from.
    ///   - signingKeys: The signing keys required to sign the transaction.
    /// - Returns: A transaction that withdraws rewards.
    /// - Throws: CardanoException if the transaction could not be created.
    func withdrawRewards(
        from stakeVerificationKey: StakeVerificationKey,
        to toAddress: Address? = nil,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        let stakeAddress = try Address(
            stakingPart: .verificationKeyHash(try stakeVerificationKey.hash()),
            network: self.txBuilder.context.networkId
        )
        
        let stakeAddressInfo = try await self.txBuilder.context.stakeAddressInfo(
            address: stakeAddress
        )
        
        guard !stakeAddressInfo.isEmpty else {
            throw CardanoTxBuilderError.invalidTransaction(
                "No rewards available to withdraw for stake address: \(stakeAddress)"
            )
        }
        
        let rewardsSum = stakeAddressInfo.reduce(0) { partialResult, info in
            partialResult + info.rewardAccountBalance
        }
        
        guard rewardsSum > 0 else {
            throw CardanoTxBuilderError.invalidTransaction(
                "Rewards sum is 0, no rewards to withdraw for: \(stakeAddress)"
            )
        }
        
        let withdrawals = Withdrawals([
            stakeAddress.toBytes(): Coin(rewardsSum)
        ])
        
        if self.txBuilder.inputs.isEmpty {
            let utxos = try await self.txBuilder.context.utxos(
                address: feePaymentAddress
            )
            for utxo in utxos {
                self.txBuilder.addInput(utxo)
            }
        }
        
        if let toAddress = toAddress, toAddress != feePaymentAddress {
            try self.txBuilder.addOutput(
                TransactionOutput(
                    address: toAddress,
                    amount: Value(coin: rewardsSum)
                )
            )
        }
        
        self.txBuilder.withdrawals = withdrawals
        
        if signingKeys == nil || signingKeys?.isEmpty == true {
            let txBody = try await self.txBuilder.build(
                changeAddress: feePaymentAddress,
                mergeChange: true
            )
            return Transaction(
                transactionBody: txBody,
                transactionWitnessSet: try self.txBuilder.buildWitnessSet(),
                auxiliaryData: self.txBuilder.auxiliaryData
            )
        } else if let signingKeys = signingKeys, !signingKeys.isEmpty {
            let transaction = try await self.txBuilder.buildAndSign(
                signingKeys: signingKeys,
                changeAddress: feePaymentAddress,
                mergeChange: true
            )
            return transaction
        } else {
            throw CardanoTxBuilderError.invalidTransaction(
                "No signing keys provided for transaction."
            )
        }
    }
}
        

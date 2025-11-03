import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Creates a transaction that delegates a stake address to a pool operator.
    /// - Parameters:
    ///   - stakeVerificationKey: The stake verification key for the stake address to delegate
    ///   - poolOperator: The pool operator to delegate the stake address to
    ///   - feePaymentAddress: The address to pay the transaction fee from
    ///   - signingKeys: Optional signing keys to sign the transaction. If nil or empty, returns an unsigned transaction.
    /// - Returns: A transaction that delegates the stake address to the specified pool operator.
    /// - Throws: CardanoTxBuilderError if the transaction could not be created.
    func stakeDelegation(
        stakeVerificationKey: StakeVerificationKey,
        poolOperator: PoolOperator,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        // 1. Derive stake address from the stake verification key
        let stakeAddress = try Address(
            stakingPart: .verificationKeyHash(try stakeVerificationKey.hash()),
            network: self.txBuilder.context.networkId
        )
        
        // 2. Check if stake address may not be on chain
        let stakeAddressInfo = try await self.txBuilder.context.stakeAddressInfo(
            address: stakeAddress
        )
        if stakeAddressInfo.isEmpty || (
            (stakeAddressInfo.first?.active == false) && (stakeAddressInfo.first?.activeEpoch == nil)
        ) {
            throw CardanoTxBuilderError.invalidTransaction("Staking Address may not be on chain.")
        }
        
        // 3. Create stake credential and delegation certificate
        let stakeCredential = StakeCredential(
            credential: .verificationKeyHash(try stakeVerificationKey.hash())
        )
        let stakeDelegationCertificate = StakeDelegation(
            stakeCredential: stakeCredential,
            poolKeyHash: poolOperator.poolKeyHash
        )
        
        // 4. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 5. Add the stake delegation certificate
        self.txBuilder.certificates = [
            .stakeDelegation(stakeDelegationCertificate)
        ]
        
        // 6. Build and optionally sign the transaction
        if signingKeys == nil || signingKeys?.isEmpty == true {
            let txBody = try await self.txBuilder.build(
                changeAddress: feePaymentAddress
            )
            return Transaction(
                transactionBody: txBody,
                transactionWitnessSet: try self.txBuilder.buildWitnessSet(),
                auxiliaryData: self.txBuilder.auxiliaryData
            )
        } else if let signingKeys = signingKeys, !signingKeys.isEmpty {
            let transaction = try await self.txBuilder.buildAndSign(
                signingKeys: signingKeys,
                changeAddress: feePaymentAddress
            )
            return transaction
        } else {
            throw CardanoTxBuilderError.invalidTransaction(
                "No signing keys provided for transaction."
            )
        }
    }
}


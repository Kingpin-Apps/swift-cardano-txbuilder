import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Creates a transaction that delegates a stake address to a DRep for voting purposes.
    /// - Parameters:
    ///   - stakeVerificationKey: The stake verification key for the stake address to delegate
    ///   - drep: The DRep to delegate the stake address to
    ///   - feePaymentAddress: The address to pay the transaction fee from
    ///   - signingKeys: Optional signing keys to sign the transaction. If nil or empty, returns an unsigned transaction.
    /// - Returns: A transaction that delegates the stake address to the DRep
    /// - Throws: CardanoTxBuilderError if the transaction could not be created.
    func voteDelegation(
        stakeVerificationKey: StakeVerificationKey,
        drep: DRep,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        
        // 1. Create stake credential and delegation certificate
        let stakeCredential = StakeCredential(
            credential: .verificationKeyHash(try stakeVerificationKey.hash())
        )
        let voteDelegationCertificate = VoteDelegate(
            stakeCredential: stakeCredential,
            drep: drep
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the stake delegation certificate
        self.txBuilder.certificates = [
            .voteDelegate(voteDelegationCertificate)
        ]
        
        // 4. Build and optionally sign the transaction
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


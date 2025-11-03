import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Creates a transaction that registers a vote delegation for a stake address.
    /// - Parameters:
    ///   - stakeVerificationKey: The stake verification key for the stake address.
    ///   - drep: The DRep to delegate votes to.
    ///   - feePaymentAddress: The address to pay transaction fees from.
    ///   - signingKeys: Optional array of signing keys to sign the transaction. If nil or empty, the transaction will not be signed.
    /// - Returns: The constructed transaction.
    /// - Throws: An error if the transaction could not be built or signed.
    func voteRegisterAndDelegation(
        stakeVerificationKey: StakeVerificationKey,
        drep: DRep,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        
        let protocolParams = try await self.txBuilder.context.protocolParameters()
        
        // 1. Create stake credential and delegation certificate
        let stakeCredential = StakeCredential(
            credential: .verificationKeyHash(try stakeVerificationKey.hash())
        )
        let voteRegisterDelegationCertificate = VoteRegisterDelegate(
            stakeCredential: stakeCredential,
            drep: drep,
            coin: Coin(protocolParams.dRepDeposit)
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the stake delegation certificate
        self.txBuilder.certificates = [
            .voteRegisterDelegate(voteRegisterDelegationCertificate)
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


import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Authenticate a committee hot key with a committee cold key.
    /// - Parameters:
    ///   - committeeColdCredential: The committee cold credential.
    ///   - committeeHotCredential: The committee hot credential.
    ///   - feePaymentAddress: The address to pay the transaction fee from.
    ///   - signingKeys: The signing keys to sign the transaction with. If `nil`, the transaction will not be signed.
    /// - Returns: The constructed transaction.
    /// - Throws: CardanoTxBuilderError if the transaction could not be constructed.
    func authCommitteeHot(
        committeeColdCredential: CommitteeColdCredential,
        committeeHotCredential: CommitteeHotCredential,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        
        // 1. Create the certificate
        let authCommitteeHotCertificate = AuthCommitteeHot(
            committeeColdCredential: committeeColdCredential,
            committeeHotCredential: committeeHotCredential
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the stake registration certificate
        self.txBuilder.certificates = [
            .authCommitteeHot(authCommitteeHotCertificate)
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

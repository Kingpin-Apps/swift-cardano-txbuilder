import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Updates a DRep credential on the blockchain.
    /// - Parameters:
    ///   - drepCredential: The DRep credential to be updated.
    ///   - anchor: Optional anchor for the update.
    ///   - feePaymentAddress: The address to pay the transaction fee from.
    ///   - signingKeys: Optional array of signing keys to sign the transaction.
    /// - Returns: The constructed transaction.
    /// - Throws: An error if the transaction cannot be built or signed.
    func updateDRep(
        drepCredential: DRepCredential,
        anchor: Anchor? = nil,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        
        // 1. Create the certificate
        let updateDRepCertificate = UpdateDRep(
            drepCredential: drepCredential,
            anchor: anchor
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the certificate
        self.txBuilder.certificates = [
            .updateDRep(updateDRepCertificate)
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

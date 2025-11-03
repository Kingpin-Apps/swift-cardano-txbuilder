import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Registers a DRep on the blockchain.
    /// - Parameters:
    ///   - drepCredential: The DRep credential to register.
    ///   - anchor: The optional anchor for the registration.
    ///   - feePaymentAddress: The address to pay the transaction fee from.
    ///   - signingKeys: The optional signing keys to sign the transaction.
    /// - Returns: The constructed transaction.
    /// - Throws: CardanoTxBuilderError if the transaction could not be built or signed.
    func registerDRep(
        drepCredential: DRepCredential,
        anchor: Anchor? = nil,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        
        let protocolParams = try await self.txBuilder.context.protocolParameters()
        
        // 1. Create the certificate
        let registerDRepCertificate = RegisterDRep(
            drepCredential: drepCredential,
            coin: Coin(protocolParams.stakeAddressDeposit),
            anchor: anchor
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the certificate
        self.txBuilder.certificates = [
            .registerDRep(registerDRepCertificate)
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

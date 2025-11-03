import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Creates a pool registration transaction.
    /// - Parameters:
    ///   - poolParams: The parameters of the stake pool to register.
    ///   - feePaymentAddress: The address to pay the transaction fee from and receive change.
    ///   - signingKeys: The signing keys to sign the transaction with. If nil or empty, the transaction will not be signed.
    /// - Returns: The constructed (and optionally signed) transaction.
    /// - Throws: An error if the transaction could not be built or signed.
    func poolRegistration(
        poolParams: PoolParams,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        // 1. Create the certificate
        let poolRegistrationCertificate = PoolRegistration(
            poolParams: poolParams,
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the certificate
        self.txBuilder.certificates = [
            .poolRegistration(poolRegistrationCertificate)
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


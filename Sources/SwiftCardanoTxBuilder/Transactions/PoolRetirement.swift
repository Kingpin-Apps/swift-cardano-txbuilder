import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Create a pool retirement transaction.
    /// - Parameters:
    ///   - poolOperator: The pool operator information.
    ///   - epoch: The epoch in which the pool will be retired.
    ///   - feePaymentAddress: The address to pay the transaction fee from.
    ///   - signingKeys: The signing keys to sign the transaction with. If nil or empty, the transaction will not be signed.
    /// - Returns: The constructed (and optionally signed) transaction.
    /// - Throws: CardanoTxBuilderError if the transaction could not be built or signed.
    func poolRetirement(
        poolOperator: PoolOperator,
        epoch: Int,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        // 1. Create the certificate
        let poolRetirementCertificate = PoolRetirement(
            poolKeyHash: poolOperator.poolKeyHash,
            epoch: epoch
        )
        
        // 2. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 3. Add the certificate
        self.txBuilder.certificates = [
            .poolRetirement(poolRetirementCertificate)
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


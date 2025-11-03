import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Create witnesses for a transaction using the provided signing keys.
    /// - Parameters:
    ///   - transaction: The transaction to be witnessed.
    ///   - keys: An array of signing keys to create witnesses.
    /// - Returns: An array of `VerificationKeyWitness` objects.
    /// - Throws: An error if signing fails.
    func witness(
        transaction: Transaction,
        keys: [SigningKeyType]
    ) throws -> [VerificationKeyWitness] {
        return try keys.map { key in
            let vkey = try key.toVerificationKeyType()
            let txBodyHash = transaction.transactionBody.hash()
            let signature = try key.sign(data: txBodyHash)
            return VerificationKeyWitness(
                vkey: vkey,
                signature: signature
            )
        }
    }
}

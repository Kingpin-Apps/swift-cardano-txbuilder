import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Signs a transaction with the provided signing keys.
    /// - Parameters:
    ///   - transaction: The transaction to be signed.
    ///   - keys: An array of signing keys to sign the transaction.
    /// - Returns: The signed transaction.
    func sign(
        transaction: Transaction,
        keys: [SigningKeyType],
    ) async throws -> Transaction {
        let vkeyWitnesses = try self.witness(
            transaction: transaction,
            keys: keys
        )
        
        return self.assemble(
            transaction: transaction,
            vkeyWitnesses: .nonEmptyOrderedSet(
                NonEmptyOrderedSet(vkeyWitnesses)
            )
        )
    }
}
        

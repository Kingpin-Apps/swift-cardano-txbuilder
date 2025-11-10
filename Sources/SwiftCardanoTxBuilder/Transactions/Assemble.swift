import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Assemble a new transaction by merging the provided witness components into the given transaction.
    ///
    /// This method creates a copy of the provided transaction and merges the specified witness
    /// components into its witness set. Most witness types are merged by concatenation (existing + new),
    /// but redeemers are replaced entirely if provided.
    ///
    /// - Parameters:
    ///   - transaction: The base transaction to be updated. A copy is made and returned (struct value semantics).
    ///   - vkeyWitnesses: Optional verification key witnesses to merge into the transaction's witness set.
    ///   - nativeScripts: Optional native scripts to merge.
    ///   - bootstrapWitness: Optional bootstrap witnesses to merge.
    ///   - plutusV1Script: Optional Plutus V1 scripts to merge.
    ///   - plutusData: Optional Plutus data (datums) to merge.
    ///   - redeemers: Optional redeemers. If provided, they replace any existing redeemers (no merge).
    ///   - plutusV2Script: Optional Plutus V2 scripts to merge.
    ///   - plutusV3Script: Optional Plutus V3 scripts to merge.
    /// - Returns: A new Transaction with its witness set updated per the provided components.
    ///
    /// # Example
    /// ```swift
    /// let updated = txBuilder.transactions.assemble(
    ///     transaction: tx,
    ///     vkeyWitnesses: .list([vkWitness1, vkWitness2]),
    ///     redeemers: .list([Redeemer(tag: .spend, index: 0, data: datum, exUnits: exUnits)])
    /// )
    /// ```
    func assemble(
        transaction: Transaction,
        vkeyWitnesses: ListOrNonEmptyOrderedSet<VerificationKeyWitness>? = nil,
        nativeScripts: ListOrNonEmptyOrderedSet<NativeScript>? = nil,
        bootstrapWitness: ListOrNonEmptyOrderedSet<BootstrapWitness>? = nil,
        plutusV1Script: ListOrNonEmptyOrderedSet<PlutusV1Script>? = nil,
        plutusData: ListOrNonEmptyOrderedSet<PlutusData>? = nil,
        redeemers: Redeemers? = nil,
        plutusV2Script: ListOrNonEmptyOrderedSet<PlutusV2Script>? = nil,
        plutusV3Script: ListOrNonEmptyOrderedSet<PlutusV3Script>? = nil
    ) -> Transaction {
        let tx = transaction // struct copy
        var ws = tx.transactionWitnessSet
        
        if let vkeyWitnesses {
            ws.vkeyWitnesses = _updateWitnessSet(existing: ws.vkeyWitnesses, toAdd: vkeyWitnesses)
        }
        
        if let nativeScripts {
            ws.nativeScripts = _updateWitnessSet(existing: ws.nativeScripts, toAdd: nativeScripts)
        }
        
        if let bootstrapWitness {
            ws.bootstrapWitness = _updateWitnessSet(existing: ws.bootstrapWitness, toAdd: bootstrapWitness)
        }
        
        if let plutusV1Script {
            ws.plutusV1Script = _updateWitnessSet(existing: ws.plutusV1Script, toAdd: plutusV1Script)
        }
        
        if let plutusData {
            ws.plutusData = _updateWitnessSet(existing: ws.plutusData, toAdd: plutusData)
        }
        
        // Special case: redeemers replace rather than merge
        if let redeemers {
            ws.redeemers = redeemers
        }
        
        if let plutusV2Script {
            ws.plutusV2Script = _updateWitnessSet(existing: ws.plutusV2Script, toAdd: plutusV2Script)
        }
        
        if let plutusV3Script {
            ws.plutusV3Script = _updateWitnessSet(existing: ws.plutusV3Script, toAdd: plutusV3Script)
        }
        
        // Return a new Transaction with properly updated _payload
        return Transaction(
            transactionBody: tx.transactionBody,
            transactionWitnessSet: ws,
            valid: tx.valid,
            auxiliaryData: tx.auxiliaryData
        )
    }
    
    /// Helper function to merge witness sets by concatenating lists.
    /// Preserves insertion order: existing witnesses first, then new witnesses.
    /// - Parameters:
    ///   - existing: The existing witness set (may be nil).
    ///   - toAdd: The new witnesses to add (may be nil).
    /// - Returns: The merged witness set, or nil if both inputs are nil.
    @inline(__always)
    private func _updateWitnessSet<T>(
        existing: ListOrNonEmptyOrderedSet<T>?,
        toAdd: ListOrNonEmptyOrderedSet<T>?
    ) -> ListOrNonEmptyOrderedSet<T>? {
        guard let toAdd else { return existing }
        guard let existing else { return toAdd }
        let combined = existing.asList + toAdd.asList
        return .list(combined)
    }
}

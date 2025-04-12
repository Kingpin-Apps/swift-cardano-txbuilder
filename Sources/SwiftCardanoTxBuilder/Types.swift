import Foundation
import SwiftCardanoCore

// MARK: - Supporting Types

/// Union type for script or UTxO input
public enum ScriptOrUTxO {
    case script(ScriptType)
    case utxo(UTxO)
}

/// Union type for UTxO or TransactionInput
public enum UTxOOrTransactionInput: Hashable {
    case utxo(UTxO)
    case input(TransactionInput)
}

/// Union type for Address or String
public enum AddressOrString {
    case address(Address)
    case string(String)
}

// MARK: - Extensions

public extension ScriptOrUTxO {
    var asUTxO: UTxO? {
        if case .utxo(let utxo) = self {
            return utxo
        }
        return nil
    }
    
    var asScript: ScriptType? {
        if case .script(let script) = self {
            return script
        }
        return nil
    }
}

public extension UTxOOrTransactionInput {
    var asUTxO: UTxO? {
        if case .utxo(let utxo) = self {
            return utxo
        }
        return nil
    }
    
    var asInput: TransactionInput? {
        if case .input(let input) = self {
            return input
        }
        return nil
    }
}

public extension AddressOrString {
    var asAddress: Address? {
        switch self {
            case .address(let address):
                return address
            case .string(let string):
                return try? Address(from: string)
        }
    }
    
    var asString: String? {
        switch self {
            case .address(let address):
                return try? address.toBech32()
            case .string(let string):
                return string
        }
    }
}

import Foundation

/// Errors that can occur during the building of a Cardano transaction.
enum CardanoTxBuilderError: Error, CustomStringConvertible, Equatable {
    case insufficientBalance(String?)
    case insufficientUTxOBalance(String?)
    case maxInputCountExceeded(String?)
    case inputUTxODepleted(String?)
    case invalidArgument(String?)
    case invalidInput(String?)
    case invalidState(String?)
    case invalidTransaction(String?)
    case transactionTooLarge(String?)
    case utxoSelectionFailed(String?)
    case valueError(String?)
    
    var description: String {
        switch self {
            case .insufficientUTxOBalance(let message):
                return message ?? "Insufficient UTXO balance."
            case .maxInputCountExceeded(let message):
                return message ?? "Max input count exceeded."
            case .inputUTxODepleted(let message):
                return message ?? "Input UTXO depleted."
            case .invalidArgument(let message):
                return message ?? "Invalid argument error occurred."
            case .invalidInput(let message):
                return message ?? "Invalid input error occurred."
            case .valueError(let message):
                return message ?? "The value is invalid."
            case .utxoSelectionFailed(let message):
                return message ?? "UTxO selection failed."
            case .insufficientBalance(let message):
                return message ?? "Insufficient balance."
            case .invalidState(let message):
                return message ?? "Invalid state."
            case .invalidTransaction(let message):
                return message ?? "Invalid transaction."
            case .transactionTooLarge(let message):
                return message ?? "Transaction too large."
        }
    }
}

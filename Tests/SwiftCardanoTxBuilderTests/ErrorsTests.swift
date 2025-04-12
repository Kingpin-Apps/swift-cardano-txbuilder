import Testing

@testable import SwiftCardanoTxBuilder

@Suite("CardanoTxBuilderError Tests")
struct CardanoTxBuilderErrorTests {

    @Test("Error descriptions with default messages")
    func testDefaultErrorDescriptions() throws {
        #expect(
            CardanoTxBuilderError.insufficientBalance(nil).description == "Insufficient balance.")
        #expect(
            CardanoTxBuilderError.insufficientUTxOBalance(nil).description
                == "Insufficient UTXO balance.")
        #expect(
            CardanoTxBuilderError.maxInputCountExceeded(nil).description
                == "Max input count exceeded.")
        #expect(CardanoTxBuilderError.inputUTxODepleted(nil).description == "Input UTXO depleted.")
        #expect(
            CardanoTxBuilderError.invalidArgument(nil).description
                == "Invalid argument error occurred.")
        #expect(
            CardanoTxBuilderError.invalidInput(nil).description == "Invalid input error occurred.")
        #expect(CardanoTxBuilderError.invalidState(nil).description == "Invalid state.")
        #expect(CardanoTxBuilderError.invalidTransaction(nil).description == "Invalid transaction.")
        #expect(
            CardanoTxBuilderError.transactionTooLarge(nil).description == "Transaction too large.")
        #expect(
            CardanoTxBuilderError.utxoSelectionFailed(nil).description == "UTxO selection failed.")
        #expect(CardanoTxBuilderError.valueError(nil).description == "The value is invalid.")
    }

    @Test("Error descriptions with custom messages")
    func testCustomErrorDescriptions() throws {
        #expect(
            CardanoTxBuilderError.insufficientBalance("Not enough ADA").description
                == "Not enough ADA")
        #expect(
            CardanoTxBuilderError.insufficientUTxOBalance("Missing UTxO funds").description
                == "Missing UTxO funds")
        #expect(
            CardanoTxBuilderError.maxInputCountExceeded("Too many inputs").description
                == "Too many inputs")
        #expect(
            CardanoTxBuilderError.inputUTxODepleted("No more UTxOs").description == "No more UTxOs")
        #expect(
            CardanoTxBuilderError.invalidArgument("Wrong parameter").description
                == "Wrong parameter")
        #expect(CardanoTxBuilderError.invalidInput("Bad input").description == "Bad input")
        #expect(
            CardanoTxBuilderError.invalidState("Invalid state found").description
                == "Invalid state found")
        #expect(
            CardanoTxBuilderError.invalidTransaction("Transaction invalid").description
                == "Transaction invalid")
        #expect(
            CardanoTxBuilderError.transactionTooLarge("Exceeds size limit").description
                == "Exceeds size limit")
        #expect(
            CardanoTxBuilderError.utxoSelectionFailed("Cannot select UTxOs").description
                == "Cannot select UTxOs")
        #expect(CardanoTxBuilderError.valueError("Invalid amount").description == "Invalid amount")
    }

    @Test("Error equality")
    func testErrorEquality() throws {
        // Test equality for errors with nil messages
        #expect(
            CardanoTxBuilderError.insufficientBalance(nil)
                == CardanoTxBuilderError.insufficientBalance(nil))

        // Test equality for errors with same messages
        #expect(
            CardanoTxBuilderError.insufficientBalance("Not enough ADA")
                == CardanoTxBuilderError.insufficientBalance("Not enough ADA")
        )

        // Test inequality for different error types
        #expect(
            CardanoTxBuilderError.insufficientBalance(nil)
                != CardanoTxBuilderError.invalidInput(nil)
        )

        // Test inequality for same error type with different messages
        #expect(
            CardanoTxBuilderError.insufficientBalance("Message 1")
                != CardanoTxBuilderError.insufficientBalance("Message 2")
        )
    }
}

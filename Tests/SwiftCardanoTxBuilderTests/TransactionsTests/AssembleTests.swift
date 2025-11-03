import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("Transactions.Assemble")
struct AssembleTests {
    
    // MARK: - Helper Functions
    
    /// Creates a minimal transaction body for testing
    func createMinimalTransactionBody() -> TransactionBody {
        let txIn = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0x01, count: 32)),
            index: 0
        )
        let txOut = TransactionOutput(
            address: try! Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x")),
            amount: Value(coin: 1_000_000)
        )
        return TransactionBody(
            inputs: .list([txIn]),
            outputs: [txOut],
            fee: 170_000
        )
    }
    
    /// Creates a minimal transaction for testing
    func createMinimalTransaction(witnessSet: TransactionWitnessSet? = nil) -> Transaction {
        return Transaction(
            transactionBody: createMinimalTransactionBody(),
            transactionWitnessSet: witnessSet ?? TransactionWitnessSet(),
            valid: true,
            auxiliaryData: nil
        )
    }
    
    /// Creates a verification key witness for testing
    func createVKeyWitness(index: Int = 0) throws -> VerificationKeyWitness {
        let vkeyData = Data(repeating: UInt8(index), count: 32)
        let signatureData = Data(repeating: UInt8(index + 1), count: 64)
        let vkey = VerificationKey(payload: vkeyData, type: nil, description: nil)
        return VerificationKeyWitness(vkey: .verificationKey(vkey), signature: signatureData)
    }
    
    /// Creates a redeemer for testing
    func createRedeemer(tag: RedeemerTag, index: Int) -> Redeemer {
        return Redeemer(
            tag: tag,
            index: index,
            data: PlutusData.constructor(Constr(tag: 0, fields: [])),
            exUnits: ExecutionUnits(mem: 1000, steps: 2000)
        )
    }
    
    // MARK: - Tests for vkeyWitnesses
    
    @Test func mergesVKeyWitnessesWhenBothPresent() throws {
        // Arrange: Create a transaction with existing witnesses
        let existingWitness = try createVKeyWitness(index: 0)
        let existingWitnessSet = TransactionWitnessSet(
            vkeyWitnesses: .list([existingWitness])
        )
        let tx = createMinimalTransaction(witnessSet: existingWitnessSet)
        
        let newWitness1 = try createVKeyWitness(index: 1)
        let newWitness2 = try createVKeyWitness(index: 2)
        let newWitnesses: ListOrNonEmptyOrderedSet<VerificationKeyWitness> = .list([newWitness1, newWitness2])
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new witnesses
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            vkeyWitnesses: newWitnesses
        )
        
        // Assert: Should have all three witnesses
        #expect(updated.transactionWitnessSet.vkeyWitnesses != nil)
        let witnesses = updated.transactionWitnessSet.vkeyWitnesses!.asList
        #expect(witnesses.count == 3, "Should have 3 witnesses total")
        #expect(witnesses[0].vkey.payload == existingWitness.vkey.payload)
        #expect(witnesses[1].vkey.payload == newWitness1.vkey.payload)
        #expect(witnesses[2].vkey.payload == newWitness2.vkey.payload)
    }
    
    @Test func setsVKeyWitnessesWhenExistingNil() throws {
        // Arrange: Create a transaction without witnesses
        let tx = createMinimalTransaction()
        
        let newWitness = try createVKeyWitness(index: 0)
        let newWitnesses: ListOrNonEmptyOrderedSet<VerificationKeyWitness> = .list([newWitness])
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new witnesses
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            vkeyWitnesses: newWitnesses
        )
        
        // Assert: Should have the new witness
        #expect(updated.transactionWitnessSet.vkeyWitnesses != nil)
        let witnesses = updated.transactionWitnessSet.vkeyWitnesses!.asList
        #expect(witnesses.count == 1, "Should have 1 witness")
        #expect(witnesses[0].vkey.payload == newWitness.vkey.payload)
    }
    
    @Test func keepsExistingWitnessesWhenNoNewProvided() throws {
        // Arrange: Create a transaction with existing witnesses
        let existingWitness = try createVKeyWitness(index: 0)
        let existingWitnessSet = TransactionWitnessSet(
            vkeyWitnesses: .list([existingWitness])
        )
        let tx = createMinimalTransaction(witnessSet: existingWitnessSet)
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble without providing new witnesses
        let updated = txBuilder.transactions.assemble(transaction: tx)
        
        // Assert: Should keep existing witness
        #expect(updated.transactionWitnessSet.vkeyWitnesses != nil)
        let witnesses = updated.transactionWitnessSet.vkeyWitnesses!.asList
        #expect(witnesses.count == 1, "Should still have 1 witness")
        #expect(witnesses[0].vkey.payload == existingWitness.vkey.payload)
    }
    
    // MARK: - Tests for Redeemers (replacement semantics)
    
    @Test func replacesRedeemersList() throws {
        // Arrange: Create a transaction with existing redeemers
        let existingRedeemer = createRedeemer(tag: .spend, index: 0)
        let existingWitnessSet = TransactionWitnessSet(
            redeemers: .list([existingRedeemer])
        )
        let tx = createMinimalTransaction(witnessSet: existingWitnessSet)
        
        let newRedeemer1 = createRedeemer(tag: .mint, index: 1)
        let newRedeemer2 = createRedeemer(tag: .cert, index: 2)
        let newRedeemers: Redeemers = .list([newRedeemer1, newRedeemer2])
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new redeemers
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            redeemers: newRedeemers
        )
        
        // Assert: Should replace with new redeemers (not merge)
        #expect(updated.transactionWitnessSet.redeemers != nil)
        
        if case let .list(redeemers) = updated.transactionWitnessSet.redeemers! {
            #expect(redeemers.count == 2, "Should have 2 redeemers (not 3)")
            #expect(redeemers[0].tag == .mint, "First redeemer should be mint")
            #expect(redeemers[1].tag == .cert, "Second redeemer should be cert")
        } else {
            Issue.record("Expected redeemers to be a list")
        }
    }
    
    @Test func replacesRedeemersMapWithList() throws {
        // Arrange: Create a transaction with redeemers as a map
        let existingRedeemerMap = RedeemerMap()
        let existingWitnessSet = TransactionWitnessSet(
            redeemers: .map(existingRedeemerMap)
        )
        let tx = createMinimalTransaction(witnessSet: existingWitnessSet)
        
        let newRedeemer = createRedeemer(tag: .spend, index: 0)
        let newRedeemers: Redeemers = .list([newRedeemer])
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new redeemers
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            redeemers: newRedeemers
        )
        
        // Assert: Should replace map with list
        #expect(updated.transactionWitnessSet.redeemers != nil)
        
        if case let .list(redeemers) = updated.transactionWitnessSet.redeemers! {
            #expect(redeemers.count == 1, "Should have 1 redeemer")
            #expect(redeemers[0].tag == .spend)
        } else {
            Issue.record("Expected redeemers to be a list")
        }
    }
    
    @Test func setsRedeemersWhenExistingNil() throws {
        // Arrange: Create a transaction without redeemers
        let tx = createMinimalTransaction()
        
        let newRedeemer = createRedeemer(tag: .spend, index: 0)
        let newRedeemers: Redeemers = .list([newRedeemer])
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new redeemers
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            redeemers: newRedeemers
        )
        
        // Assert: Should have the new redeemers
        #expect(updated.transactionWitnessSet.redeemers != nil)
        
        if case let .list(redeemers) = updated.transactionWitnessSet.redeemers! {
            #expect(redeemers.count == 1)
            #expect(redeemers[0].tag == .spend)
        } else {
            Issue.record("Expected redeemers to be a list")
        }
    }
    
    // MARK: - Tests for PlutusData (merge semantics)
    
    @Test func mergesPlutusDataWhenBothPresent() throws {
        // Arrange: Create a transaction with existing plutus data
        let existingDatum = PlutusData.constructor(Constr(tag: 0, fields: []))
        let existingWitnessSet = TransactionWitnessSet(
            plutusData: .list([existingDatum])
        )
        let tx = createMinimalTransaction(witnessSet: existingWitnessSet)
        
        let newDatum1 = PlutusData.constructor(Constr(tag: 1, fields: []))
        let newDatum2 = PlutusData.constructor(Constr(tag: 2, fields: []))
        let newData: ListOrNonEmptyOrderedSet<PlutusData> = .list([newDatum1, newDatum2])
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new plutus data
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            plutusData: newData
        )
        
        // Assert: Should have all three datums
        #expect(updated.transactionWitnessSet.plutusData != nil)
        let data = updated.transactionWitnessSet.plutusData!.asList
        #expect(data.count == 3, "Should have 3 datums total")
    }
    
    // MARK: - Tests for multiple witness types
    
    @Test func assemblesMultipleWitnessTypes() throws {
        // Arrange: Create a base transaction
        let tx = createMinimalTransaction()
        
        let vkeyWitness = try createVKeyWitness(index: 0)
        let redeemer = createRedeemer(tag: .spend, index: 0)
        let datum = PlutusData.constructor(Constr(tag: 0, fields: []))
        
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with multiple witness types
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            vkeyWitnesses: .list([vkeyWitness]),
            plutusData: .list([datum]),
            redeemers: .list([redeemer])
        )
        
        // Assert: Should have all witness types
        #expect(updated.transactionWitnessSet.vkeyWitnesses != nil)
        #expect(updated.transactionWitnessSet.vkeyWitnesses!.asList.count == 1)
        
        #expect(updated.transactionWitnessSet.plutusData != nil)
        #expect(updated.transactionWitnessSet.plutusData!.asList.count == 1)
        
        #expect(updated.transactionWitnessSet.redeemers != nil)
        if case let .list(redeemers) = updated.transactionWitnessSet.redeemers! {
            #expect(redeemers.count == 1)
        } else {
            Issue.record("Expected redeemers to be a list")
        }
    }
    
    @Test func doesNotModifyOriginalTransaction() throws {
        // Arrange: Create a transaction with witnesses
        let existingWitness = try createVKeyWitness(index: 0)
        let existingWitnessSet = TransactionWitnessSet(
            vkeyWitnesses: .list([existingWitness])
        )
        let tx = createMinimalTransaction(witnessSet: existingWitnessSet)
        
        let originalWitnessCount = tx.transactionWitnessSet.vkeyWitnesses!.asList.count
        
        let newWitness = try createVKeyWitness(index: 1)
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new witnesses
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            vkeyWitnesses: .list([newWitness])
        )
        
        // Assert: Original transaction should remain unchanged (value semantics)
        #expect(tx.transactionWitnessSet.vkeyWitnesses!.asList.count == originalWitnessCount)
        #expect(updated.transactionWitnessSet.vkeyWitnesses!.asList.count == originalWitnessCount + 1)
    }
    
    @Test func preservesOtherTransactionProperties() throws {
        // Arrange: Create a transaction with specific properties
        let tx = createMinimalTransaction()
        let originalValid = tx.valid
        let originalBodyFee = tx.transactionBody.fee
        let originalBodyInputsCount = tx.transactionBody.inputs.count
        
        let vkeyWitness = try createVKeyWitness(index: 0)
        let txBuilder = TxBuilder(context: MockChainContext())
        
        // Act: Assemble with new witnesses
        let updated = txBuilder.transactions.assemble(
            transaction: tx,
            vkeyWitnesses: .list([vkeyWitness])
        )
        
        // Assert: Non-witness properties should remain unchanged
        #expect(updated.valid == originalValid)
        #expect(updated.transactionBody.fee == originalBodyFee)
        #expect(updated.transactionBody.inputs.count == originalBodyInputsCount)
    }
}

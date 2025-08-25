import Testing
import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
@testable import SwiftCardanoTxBuilder

@Suite("TxBuilder Tests")
struct TxBuilderTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"
    
    @Test func testBasicTransaction() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder<Never, MockChainContext>(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        // Add sender address as input
        txBuilder.addInputAddress(.string(sender))
        try txBuilder
            .addOutput(try TransactionOutput(from: sender, amount: 500000))
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        print(txBody)
        #expect(txBody.inputs.count > 0)
        #expect(txBody.outputs.count > 0)
    }
    
    @Test func testTransactionWithNoChange() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder<Never, MockChainContext>(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        txBuilder.addInputAddress(.address(senderAddress))
        
        let tx_output = try TransactionOutput(from: .list([.string(sender), .int(500000)]))
        try txBuilder.addOutput(tx_output)
        
        let txBody = try await txBuilder.build()
        
        #expect(txBody.inputs.count > 0)
        #expect(txBody.outputs.count > 0)
    }
    
    @Test func testTransactionWithSpecificInput() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder<Never, MockChainContext>(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let txIn1 = try TransactionInput(from: .list([
            .bytes(Data(repeating: 2, count: 32)),
            .int(1)
        ]))
        let txOut1 = try TransactionOutput(from: .list([
            .string(sender),
            .list([
                .int(6000000),
                .dict([
                    .bytes(Data(repeating: 1, count: 28)): .dict([
                        .string("Token1"): .int(1), .string("Token2"): .int(2)
                    ])
                ])
            ])
        ]))
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        txBuilder.addInput(utxo1)
        try txBuilder
            .addOutput(
                TransactionOutput(from: .list([.string(sender), .int(500000)]))
            )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        #expect(txBody.inputs.contains(txIn1))
        #expect(txBody.outputs.count > 0)
    }
    
    @Test func testTransactionWithMultiAsset() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder<Never, MockChainContext>(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        try txBuilder
            .addInputAddress(.address(senderAddress))
            .addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(coin: 1_000_000)
                )
            ).addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(
                        coin: 1_000_000,
                        multiAsset: MultiAsset(from: [
                            Data(repeating: 1, count: 28).toHex: ["Token1".toData.toHex: 1]
                        ])
                    )
                )
            )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        #expect(txBody.inputs.count > 0)
        #expect(txBody.outputs.count > 1)
    }
    
//    @Test func testTransactionWithInsufficientFunds() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 1000000000]))
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([
//            sender,
//            [2000000, [Data(repeating: 1, count: 28): ["NewToken": 1]]]
//        ]))
//        
//        #expect(throws: UTxOSelectionException.self) {
//        #    try txBuilder.build(changeAddress: senderAddress)
//        #}
//    }
//    
//    @Test func testTransactionWithMinting() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let mint = [policyId.payload: ["Token1": 1]]
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, [2000000, mint]]))
//        txBuilder.mint = MultiAsset.fromPrimitive(mint)
//        txBuilder.nativeScripts = [script]
//        txBuilder.ttl = 123456789
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 1)
//    }
//    
//    @Test func testTransactionWithBurning() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -1]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [policyId.payload: ["Token1": 1]]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.contains(txInput))
//    }
//    
//    @Test func testTransactionWithCertificates() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let stakeKeyHash = VerificationKeyHash(Data(repeating: 1, count: 28))
//        let stakeCredential = StakeCredential(stakeKeyHash)
//        let poolHash = PoolKeyHash(Data(repeating: 1, count: 28))
//        
//        let stakeRegistration = StakeRegistration(stakeCredential)
//        let stakeDelegation = StakeDelegation(stakeCredential, poolHash)
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        txBuilder.certificates = [stakeRegistration, stakeDelegation]
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.certificates?.count == 2)
//    }
//    
//    @Test func testTransactionWithWithdrawals() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let stakeAddress = try Address.fromPrimitive("stake_test1upyz3gk6mw5he20apnwfn96cn9rscgvmmsxc9r86dh0k66gswf59n")
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let withdrawals = Withdrawals([Data(stakeAddress): 10000])
//        txBuilder.withdrawals = withdrawals
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.withdrawals?.count == 1)
//    }
//    
//    @Test func testTransactionWithPotentialInputs() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let utxos = try chainContext.utxos(sender)
//        txBuilder.potentialInputs.append(contentsOf: utxos)
//        
//        // Add more potential inputs
//        for i in 0..<20 {
//            var utxo = utxos[0]
//            utxo.input.index = UInt32(i + 100)
//            txBuilder.potentialInputs.append(utxo)
//        }
//        
//        #expect(txBuilder.potentialInputs.count > 1)
//        
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([
//            sender,
//            [5000000, [Data(repeating: 1, count: 28): ["Token1": 1]]]
//        ]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count < txBuilder.potentialInputs.count)
//    }
//    
//    @Test func testTransactionWithExcludedInputs() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let utxos = try chainContext.utxos(sender)
//        txBuilder.excludedInputs.append(utxos[0])
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(!txBody.inputs.contains(utxos[0].input))
//    }
//    
//    @Test func testBuildAndSign() async throws {
//        let chainContext = try await ChainContext()
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txBuilder1 = TransactionBuilder(chainContext: chainContext)
//        txBuilder1.addInputAddress(sender)
//        txBuilder1.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder1.build(changeAddress: senderAddress)
//        
//        let txBuilder2 = TransactionBuilder(chainContext: chainContext)
//        txBuilder2.addInputAddress(sender)
//        txBuilder2.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let tx = try txBuilder2.buildAndSign(
//            signingKeys: [SK],
//            changeAddress: senderAddress,
//            forceSigningKeys: true
//        )
//        
//        #expect(tx.transactionWitnessSet.vkeyWitnesses.count > 0)
//        #expect(txBody.toCBORHex() == "a300d9010281825820313131313131313131313131313131313131313131313131313131313131313100018282581d60f6532850e1bccee9c72a9113ad98bcc5dbb30d2ac960262444f6e5f41a0007a12082581d60f6532850e1bccee9c72a9113ad98bcc5dbb30d2ac960262444f6e5f41a004222f3021a0002872d")
//    }
//    
//    @Test func testTransactionWithScriptInput() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([
//            "18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef",
//            0
//        ])
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        let scriptHash = plutusScriptHash(plutusScript)
//        let scriptAddress = Address(scriptHash)
//        let datum = PlutusData()
//        
//        let utxo1 = UTxO(
//            txIn1,
//            TransactionOutput(scriptAddress, 10000000, datumHash: datum.hash())
//        )
//        
//        let redeemer = Redeemer(PlutusData(), ExecutionUnits(1000000, 1000000))
//        txBuilder.addScriptInput(utxo1, plutusScript, datum, redeemer)
//        
//        let receiver = try Address.fromPrimitive(sender)
//        txBuilder.addOutput(TransactionOutput(receiver, 5000000))
//        
//        let txBody = try txBuilder.build(changeAddress: receiver)
//        let witness = txBuilder.buildWitnessSet()
//        
//        #expect(witness.plutusData?.contains(datum) == true)
//        #expect(witness.redeemer?.contains(redeemer) == true)
//        #expect(witness.plutusV1Script?.contains(plutusScript) == true)
//    }
//    
//    @Test func testTransactionWithMintingScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([
//            "18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef",
//            0
//        ])
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        let scriptHash = plutusScriptHash(plutusScript)
//        let scriptAddress = Address(scriptHash)
//        
//        let utxo1 = UTxO(txIn1, TransactionOutput(scriptAddress, 10000000))
//        let mint = MultiAsset.fromPrimitive([scriptHash.payload: ["TestToken": 1]])
//        let redeemer = Redeemer(PlutusData(), ExecutionUnits(1000000, 1000000))
//        
//        txBuilder.mint = mint
//        txBuilder.addInput(utxo1)
//        txBuilder.addMintingScript(plutusScript, redeemer)
//        
//        let receiver = try Address.fromPrimitive(sender)
//        txBuilder.addOutput(TransactionOutput(receiver, Value(5000000, mint)))
//        
//        let txBody = try txBuilder.build(changeAddress: receiver)
//        let witness = txBuilder.buildWitnessSet()
//        
//        #expect(witness.plutusV1Script?.contains(plutusScript) == true)
//    }
//    
//    @Test func testTransactionWithCollateral() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([
//            "18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef",
//            0
//        ])
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        let scriptHash = plutusScriptHash(plutusScript)
//        let scriptAddress = Address(scriptHash)
//        let datum = PlutusData()
//        
//        let utxo1 = UTxO(
//            txIn1,
//            TransactionOutput(scriptAddress, 10000000, datumHash: datum.hash())
//        )
//        
//        let redeemer = Redeemer(PlutusData(), ExecutionUnits(1000000, 1000000))
//        txBuilder.addScriptInput(utxo1, datum: datum, redeemer: redeemer)
//        
//        let receiver = try Address.fromPrimitive(sender)
//        txBuilder.addOutput(TransactionOutput(receiver, 5000000))
//        
//        let txBody = try txBuilder.build(changeAddress: receiver)
//        
//        #expect(txBody.collateralReturn?.address == receiver)
//    }
//    
//    @Test func testTransactionWithMergeChange() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let inputAmount = 10000000
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, inputAmount])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addInput(utxo1)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 10000]))
//        
//        let txBody = try txBuilder.build(
//            changeAddress: senderAddress,
//            mergeChange: true
//        )
//        
//        #expect(txBody.outputs.count == 1)
//    }
//    
//    @Test func testTransactionWithZeroAmountOutput() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let inputAmount = 10000000
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, inputAmount])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addInput(utxo1)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 0]))
//        
//        let txBody = try txBuilder.build(
//            changeAddress: senderAddress,
//            mergeChange: true
//        )
//        
//        #expect(txBody.outputs.count == 1)
//    }
//    
//    @Test func testTransactionWithSmallUTxO() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([
//            "41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7",
//            1
//        ])
//        let txOut1 = try TransactionOutput.fromPrimitive([
//            "addr1qytqt3v9ej3kzefxcy8f59h9atf2knracnj5snkgtaea6p4r8g3mu652945v3gldw7v88dn5lrfudx0un540ak9qt2kqhfjl0d",
//            2991353
//        ])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addInput(utxo1)
//        txBuilder.addOutput(TransactionOutput(
//            try Address.fromPrimitive("addr1qyady0evsaxqsfmz0z8rvmq62fmuas5w8n4m8z6qcm4wrt3e8dlsen8n464ucw69acfgdxgguscgfl5we3rwts4s57ashysyee"),
//            Value.fromPrimitive([1000000])
//        ))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTransactionTooBig() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        txBuilder.addInputAddress(sender)
//        for _ in 0..<500 {
//            txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 10]))
//        }
//        
//        #expect(throws: InvalidTransactionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testSmallUTxOPreciseFee() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, 4000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addInput(utxo1)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 2500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testSmallUTxOBalanceFail() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, 4000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addInput(utxo1)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        
//        #expect(throws: UTxOSelectionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testSmallUTxOBalancePass() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, 4000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addInput(utxo1)
//        txBuilder.addInputAddress(senderAddress)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 1)
//    }
//    
//    @Test func testChangeSplitNFTs() async throws {
//        let chainContext = try await ChainContext()
//        var protocolParam = chainContext.protocolParam
//        protocolParam.maxValSize = 50
//        chainContext.protocolParam = protocolParam
//        
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 7000000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.outputs.count > 1)
//    }
//    
//    @Test func testChangeSplitNFTsNotEnough() async throws {
//        let chainContext = try await ChainContext()
//        var protocolParam = chainContext.protocolParam
//        protocolParam.maxValSize = 50
//        chainContext.protocolParam = protocolParam
//        
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let mint = [policyId.payload: ["Token3": 1]]
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 8000000]))
//        txBuilder.mint = MultiAsset.fromPrimitive(mint)
//        txBuilder.nativeScripts = [script]
//        txBuilder.ttl = 123456789
//        
//        #expect(throws: InsufficientUTxOBalanceException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testNotEnoughInputAmount() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        let inputUtxo = try chainContext.utxos(sender)[0]
//        
//        txBuilder.addInput(inputUtxo)
//        txBuilder.addOutput(TransactionOutput(
//            try Address.fromPrimitive(sender),
//            inputUtxo.output.amount
//        ))
//        
//        #expect(throws: UTxOSelectionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testAddScriptInputNoScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        #expect(throws: InvalidTransactionException.self) {
//            try txBuilder.addScriptInput(utxo1, datum: PlutusData(), redeemer: Redeemer(PlutusData()))
//        }
//    }
//    
//    @Test func testAddScriptInputPaymentScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        txBuilder.addScriptInput(utxo1, plutusScript, PlutusData(), Redeemer(PlutusData()))
//        
//        #expect(txBuilder.scriptInputs.count == 1)
//    }
//    
//    @Test func testAddScriptInputFindScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        let scriptHash = plutusScriptHash(plutusScript)
//        let scriptAddress = Address(scriptHash)
//        let txOut1 = try TransactionOutput.fromPrimitive([scriptAddress, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addScriptInput(utxo1, datum: PlutusData(), redeemer: Redeemer(PlutusData()))
//        
//        #expect(txBuilder.scriptInputs.count == 1)
//    }
//    
//    @Test func testAddScriptInputWithScriptFromSpecifiedUtxo() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        let scriptHash = plutusScriptHash(plutusScript)
//        let scriptAddress = Address(scriptHash)
//        let txOut1 = try TransactionOutput.fromPrimitive([scriptAddress, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addScriptInput(utxo1, plutusScript, PlutusData(), Redeemer(PlutusData()))
//        
//        #expect(txBuilder.scriptInputs.count == 1)
//    }
//    
//    @Test func testAddScriptInputIncorrectScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let plutusScript1 = PlutusV1Script(Data("dummy test script 1".utf8))
//        let plutusScript2 = PlutusV1Script(Data("dummy test script 2".utf8))
//        let scriptHash = plutusScriptHash(plutusScript1)
//        let scriptAddress = Address(scriptHash)
//        let txOut1 = try TransactionOutput.fromPrimitive([scriptAddress, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        #expect(throws: InvalidTransactionException.self) {
//            try txBuilder.addScriptInput(utxo1, plutusScript2, PlutusData(), Redeemer(PlutusData()))
//        }
//    }
//    
//    @Test func testAddScriptInputNoScriptNoAttachedScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let txOut1 = try TransactionOutput.fromPrimitive([sender, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        #expect(throws: InvalidTransactionException.self) {
//            try txBuilder.addScriptInput(utxo1, datum: PlutusData(), redeemer: Redeemer(PlutusData()))
//        }
//    }
//    
//    @Test func testAddScriptInputFindIncorrectScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let plutusScript1 = PlutusV1Script(Data("dummy test script 1".utf8))
//        let plutusScript2 = PlutusV1Script(Data("dummy test script 2".utf8))
//        let scriptHash = plutusScriptHash(plutusScript1)
//        let scriptAddress = Address(scriptHash)
//        let txOut1 = try TransactionOutput.fromPrimitive([scriptAddress, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        #expect(throws: InvalidTransactionException.self) {
//            try txBuilder.addScriptInput(utxo1, plutusScript2, PlutusData(), Redeemer(PlutusData()))
//        }
//    }
//    
//    @Test func testAddScriptInputWithScriptFromSpecifiedUtxoWithIncorrectScript() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let plutusScript1 = PlutusV1Script(Data("dummy test script 1".utf8))
//        let plutusScript2 = PlutusV1Script(Data("dummy test script 2".utf8))
//        let scriptHash = plutusScriptHash(plutusScript1)
//        let scriptAddress = Address(scriptHash)
//        let txOut1 = try TransactionOutput.fromPrimitive([scriptAddress, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        #expect(throws: InvalidTransactionException.self) {
//            try txBuilder.addScriptInput(utxo1, plutusScript2, PlutusData(), Redeemer(PlutusData()))
//        }
//    }
//    
//    @Test func testAddScriptInputMultipleRedeemers() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let txIn1 = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 3])
//        let plutusScript = PlutusV1Script(Data("dummy test script".utf8))
//        let scriptHash = plutusScriptHash(plutusScript)
//        let scriptAddress = Address(scriptHash)
//        let txOut1 = try TransactionOutput.fromPrimitive([scriptAddress, 10000000])
//        let utxo1 = UTxO(txIn1, txOut1)
//        
//        txBuilder.addScriptInput(utxo1, plutusScript, PlutusData(), Redeemer(PlutusData()))
//        txBuilder.addScriptInput(utxo1, plutusScript, PlutusData(), Redeemer(PlutusData()))
//        
//        #expect(txBuilder.scriptInputs.count == 2)
//    }
//    
//    @Test func testTxBuilderStateLoggerWarningLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to warning
//        logger.logLevel = .warning
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerInfoLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to info
//        logger.logLevel = .info
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerDebugLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to debug
//        logger.logLevel = .debug
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerErrorLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to error
//        logger.logLevel = .error
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerCriticalLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to critical
//        logger.logLevel = .critical
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerTraceLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to trace
//        logger.logLevel = .trace
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerNoticeLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to notice
//        logger.logLevel = .notice
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerEmergencyLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to emergency
//        logger.logLevel = .emergency
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testTxBuilderStateLoggerAlertLevel() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        // Set logger level to alert
//        logger.logLevel = .alert
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 500000]))
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.count > 0)
//        #expect(txBody.outputs.count > 0)
//    }
//    
//    @Test func testBurningAllAssetsUnderSinglePolicy() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -1, "Token2": -1]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [policyId.payload: ["Token1": 1, "Token2": 1]]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.contains(txInput))
//    }
//    
//    @Test func testBurningAllAssetsUnderMultiplePolicies() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script1 = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let script2 = ScriptAll([before, after, spk2, ScriptAll([spk1, spk2])])
//        let policyId1 = script1.hash()
//        let policyId2 = script2.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([
//            policyId1.payload: ["Token1": -1],
//            policyId2.payload: ["Token2": -1]
//        ])
//        
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [
//                    policyId1.payload: ["Token1": 1],
//                    policyId2.payload: ["Token2": 1]
//                ]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        txBuilder.nativeScripts = [script1, script2]
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.contains(txInput))
//    }
//    
//    @Test func testBurningSomeAssetsUnderSinglePolicy() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -1]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [policyId.payload: ["Token1": 1, "Token2": 1]]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.contains(txInput))
//    }
//    
//    @Test func testBurningSomeAssetsUnderMultiplePolicies() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script1 = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let script2 = ScriptAll([before, after, spk2, ScriptAll([spk1, spk2])])
//        let policyId1 = script1.hash()
//        let policyId2 = script2.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId1.payload: ["Token1": -1]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [
//                    policyId1.payload: ["Token1": 1, "Token2": 1],
//                    policyId2.payload: ["Token3": 1, "Token4": 1]
//                ]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        txBuilder.nativeScripts = [script1]
//        
//        let txBody = try txBuilder.build(changeAddress: senderAddress)
//        
//        #expect(txBody.inputs.contains(txInput))
//    }
//    
//    @Test func testBurningAssetsWithInsufficientAda() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -1]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [100000, [policyId.payload: ["Token1": 1]]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        #expect(throws: UTxOSelectionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testBurningAssetsWithInsufficientUtxo() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -1]])
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        #expect(throws: UTxOSelectionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testBurningAssetsWithInsufficientUtxoBalance() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -2]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [policyId.payload: ["Token1": 1]]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        #expect(throws: UTxOSelectionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
//    
//    @Test func testBurningAssetsWithInsufficientUtxoCount() async throws {
//        let chainContext = try await ChainContext()
//        let txBuilder = TransactionBuilder(chainContext: chainContext)
//        let senderAddress = try Address.fromPrimitive(sender)
//        
//        let vk1 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
//        let vk2 = try VerificationKey.fromCBOR("58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
//        let spk1 = ScriptPubkey(keyHash: vk1.hash())
//        let spk2 = ScriptPubkey(keyHash: vk2.hash())
//        let before = InvalidHereAfter(123456789)
//        let after = InvalidBefore(123456780)
//        let script = ScriptAll([before, after, spk1, ScriptAll([spk1, spk2])])
//        let policyId = script.hash()
//        
//        let toBurn = MultiAsset.fromPrimitive([policyId.payload: ["Token1": -1, "Token2": -1]])
//        let txInput = try TransactionInput.fromPrimitive([Data(repeating: 1, count: 32), 123])
//        
//        txBuilder.potentialInputs.append(UTxO(
//            txInput,
//            TransactionOutput.fromPrimitive([
//                sender,
//                [2000000, [policyId.payload: ["Token1": 1]]]
//            ])
//        ))
//        
//        txBuilder.addInputAddress(sender)
//        txBuilder.addOutput(TransactionOutput.fromPrimitive([sender, 3000000]))
//        txBuilder.mint = toBurn
//        
//        #expect(throws: UTxOSelectionException.self) {
//            try txBuilder.build(changeAddress: senderAddress)
//        }
//    }
}

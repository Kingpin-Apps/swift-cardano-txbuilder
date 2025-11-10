import Testing
import Foundation
import Logging
import SwiftCardanoChain
import SwiftCardanoCore
import PotentCodables
@testable import SwiftCardanoTxBuilder

@Suite("TxBuilder Tests")
struct TxBuilderTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"
    
    @Test func testTxBuilder() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        // Add sender address as input
        try txBuilder.addInputAddress(.string(sender)).addOutput(
            TransactionOutput(from: .list([.string(sender), .uint(500000)]))
        )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        // Verify specific expected values that match PyCardano test
        #expect(txBody.inputs.count == 1)
        #expect(txBody.outputs.count == 2)
        #expect(txBody.fee == 165677)
        
        // First output should be the requested output
        let firstOutput = txBody.outputs[0]
        #expect(firstOutput.address == senderAddress)
        #expect(firstOutput.amount.coin == 500000)
        
        // Second output should be change
        let changeOutput = txBody.outputs[1]
        #expect(changeOutput.address == senderAddress)
        #expect(changeOutput.amount.coin == 4334323)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(500000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .int(4334323)
                ])
            ]),
            .uint(2): .uint(165677)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
                
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderWithNoChange() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        txBuilder.addInputAddress(.address(senderAddress))
        
        let tx_output = try TransactionOutput(from: .list([.string(sender), .uint(500_000)]))
        try txBuilder.addOutput(tx_output)
        
        let txBody = try await txBuilder.build()
        
        #expect(txBody.inputs.count > 0)
        #expect(txBody.outputs.count > 0)
    }
    
    @Test func testTxBuilderWithCertainInput() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let txIn1 = try TransactionInput(from: .list([
            .bytes(Data(repeating: 0x32, count: 32)),
            .uint(1)
        ]))
        let txOut1 = try TransactionOutput(from: .list([
            .string(sender),
            .list([
                .uint(6_000_000),
                .dict([
                    .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                        .string("Token1"): .uint(1), .string("Token2"): .uint(2)
                    ])
                ])
            ])
        ]))
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        try txBuilder
            .addInput(utxo1)
            .addOutput(
                TransactionOutput(from: .list([.string(sender), .uint(500000)]))
            )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x32, count: 32)),
                        .uint(1)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(500_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(5_332_167),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token1".toData): .int(1),
                                .bytes("Token2".toData): .int(2)
                            ])
                        ])
                    ])
                ])
            ]),
            .uint(2): .uint(167_833)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderWithPotentialInputs() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))

        let utxos = try await chainContext.utxos(address: senderAddress)
        txBuilder.potentialInputs = utxos

        // Add more potential inputs
        for i in 0..<20 {
            let utxo = utxos[0]
            let newUtxo = UTxO(
                input: try TransactionInput(from: .list([
                    .bytes(Data(repeating: 1, count: 32)),
                    .uint(UInt(UInt16(i + 100)))
                ])),
                output: utxo.output
            )
            txBuilder.potentialInputs.append(newUtxo)
        }

        #expect(txBuilder.potentialInputs.count > 1)
        
        let txOut = try TransactionOutput(from: .list([
            .string(sender),
            .list([
                .int(5000000),
                .dict([
                    .bytes(Data(repeating: 0x31, count: 28)): .dict([
                        .string("Token1"): .uint(1)
                    ])
                ])
            ])
        ]))

        try txBuilder.addOutput(txOut)

        let txBody = try await txBuilder.build(changeAddress: senderAddress)

        #expect(txBody.inputs.count < txBuilder.potentialInputs.count)
    }
    
    @Test func testTxBuilderWithMultiAsset() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        try txBuilder
            .addInputAddress(.address(senderAddress))
            .addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(coin: 3_000_000)
                )
            ).addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(
                        coin: 2_000_000,
                        multiAsset: MultiAsset(from: [
                            Data(repeating: 0x31, count: 28).toHex: ["Token1".toData.toHex: 1]
                        ])
                    )
                )
            )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        print(txBody)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ]),
                    .list([
                        .bytes(Data(repeating: 0x32, count: 32)),
                        .uint(1)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(3_000_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(2_000_000),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token1".toData): .int(1)
                            ])
                        ])
                    ])
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(5_827_503),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token2".toData): .int(2)
                            ])
                        ])
                    ])
                ])
            ]),
            .uint(2): .uint(172_497)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
        
        #expect(txBody.inputs.count > 0)
        #expect(txBody.outputs.count > 1)
    }
    
    @Test func testTxBuilderRaisesUTxOSelection() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(
            context: chainContext
        )
        let senderAddress = try Address(from: .string(sender))
        
        try txBuilder
            .addInputAddress(.address(senderAddress))
            .addOutput(
                try TransactionOutput(
                    from: .list([.string(sender), .uint(1_000_000_000)])
                )
            )
            .addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(
                        coin: 2_000_000,
                        multiAsset: MultiAsset(from: [
                            Data(repeating: 0x31, count: 28).toHex: ["NewToken".toData.toHex: 1]
                        ])
                    )
                )
            )
        
        let error =  await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.build(changeAddress: senderAddress)
        }
        
        #expect(String(describing: error).contains("coin: 991161321"))
        #expect(String(describing: error).contains("\"4e6577546f6b656e\" : 1"))
    }
    
    @Test(.disabled("Flaky when run with other tests - stderr capture is not reliable in parallel test execution"))
    func testTxBuilderStateLoggerWarningLevel() async throws {
        let output = try await captureStderr {
            let chainContext = MockChainContext()
            let txBuilder = TxBuilder(
                context: chainContext
            )
            let senderAddress = try Address(from: .string(sender))
            
            try txBuilder
                .addInputAddress(.address(senderAddress))
                .addOutput(
                    try TransactionOutput(
                        from: .list([.string(sender), .uint(1_000_000_000)])
                    )
                )
                .addOutput(
                    TransactionOutput(
                        address: senderAddress,
                        amount: Value(
                            coin: 2_000_000,
                            multiAsset: MultiAsset(from: [
                                Data(repeating: 0x31, count: 28).toHex: ["NewToken".toData.toHex: 1]
                            ])
                        )
                    )
                )
            
            let error =  await #expect(throws: CardanoTxBuilderError.self) {
                let _ = try await txBuilder.build(changeAddress: senderAddress)
            }
            
            #expect(String(describing: error).contains("coin: 991161321"))
            #expect(String(describing: error).contains("\"4e6577546f6b656e\" : 1"))
        }
        #expect(output.localizedCaseInsensitiveContains("Input UTxOs depleted!"))
    }
    
    @Test func testTxTooBig() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))

        txBuilder.addInputAddress(.address(senderAddress))
        for _ in 0..<500 {
            try txBuilder.addOutput(
                try TransactionOutput(from:
                    .list([
                        .string(sender),
                        .uint(10)
                    ])
                )
            )
        }

        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.build(changeAddress: senderAddress)
        }
    }
    
    @Test func testTxBuilderWithPotentialInput() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        let txIn1 = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut1 = TransactionOutput(address: senderAddress, amount: Value(coin: 4_000_000))
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        try txBuilder
            .addInput(utxo1)
            .addOutput(
                TransactionOutput(from: .list([.string(sender), .uint(2_500_000)]))
            )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(2_500_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .int(1_334_323)
                ])
            ]),
            .uint(2): .uint(165_677)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
                
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testSmallUTxOBalanceFail() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))

        let txIn1 = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut1 = TransactionOutput(address: senderAddress, amount: Value(coin: 4_000_000))
        let utxo1 = UTxO(input: txIn1, output: txOut1)

        txBuilder.addInput(utxo1)
        try txBuilder.addOutput(
            TransactionOutput(address: senderAddress, amount: Value(coin: 3_000_000))
        )

        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.build(changeAddress: senderAddress)
        }
    }

    @Test func testSmallUTxOBalancePass() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))

        let txIn1 = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut1 = TransactionOutput(address: senderAddress, amount: Value(coin: 4_000_000))
        let utxo1 = UTxO(input: txIn1, output: txOut1)

        txBuilder.addInput(utxo1)
        txBuilder.addInputAddress(.address(senderAddress))
        try txBuilder.addOutput(
            TransactionOutput(address: senderAddress, amount: Value(coin: 3_000_000))
        )

        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ]),
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(3_000_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .int(5_832_739)
                ])
            ]),
            .uint(2): .uint(167_261)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
                
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderMintMultiAsset() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0] // Use deterministic sequence for RandomImproveMultiAsset
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        // Create verification keys from hex data
        let vk1Data = Data(hex: "6443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
        let vk2Data = Data(hex: "6443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
        let vk1 = try VerificationKey(payload: vk1Data)
        let vk2 = try VerificationKey(payload: vk2Data)
        
        let spk1 = NativeScript.scriptPubkey(ScriptPubkey(keyHash: try vk1.hash()))
        let spk2 = NativeScript.scriptPubkey(ScriptPubkey(keyHash: try vk2.hash()))
        let before = NativeScript.invalidHereAfter(AfterScript(slot: 123456789))
        let after = NativeScript.invalidBefore(BeforeScript(slot: 123456780))
        let innerAll = NativeScript.scriptAll(ScriptAll(scripts: [spk1, spk2]))
        let script = NativeScript.scriptAll(ScriptAll(scripts: [before, after, spk1, innerAll]))
        let policyId = try script.scriptHash()
        
        // Create the mint multi-asset
        let mint = try MultiAsset(from: [
            policyId.payload.toHex: ["Token1".toData.toHex: 1]
        ])
        
        try txBuilder
            .addInputAddress(.string(sender))
            .addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(coin: 3_000_000)
                )
            )
            .addOutput(
                TransactionOutput(
                    address: senderAddress,
                    amount: Value(
                        coin: 2_000_000,
                        multiAsset: mint
                    )
                )
            )
        txBuilder.mint = mint
        txBuilder.nativeScripts = [script]
        txBuilder.ttl = 123456789
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        guard case let .verificationKeyHash(senderAddressPaymentPart) = senderAddress.paymentPart else {
            Issue.record("Sender address has no payment part")
            return
        }
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ]),
                    .list([
                        .bytes(Data(repeating: 0x32, count: 32)),
                        .uint(1)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(3_000_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(2_000_000),
                        mint.toPrimitive()
                    ])
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(5_809_155),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token1".toData): .int(1),
                                .bytes("Token2".toData): .int(2),
                            ])
                        ])
                    ])
                ])
            ]),
            .uint(2): .uint(190_845),
            .uint(3): .uint(123_456_789),
            .uint(8): .uint(1_000),
            .uint(9): mint.toPrimitive(),
            .uint(14): .nonEmptyOrderedSet(
                NonEmptyOrderedSet([
                    senderAddressPaymentPart.toPrimitive()
                ])
            ),
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        print("Expected:")
        print(expected)
        print("\nActual:")
        print(txBodyPrimitive)
        
        // Print detailed comparison
        if case .orderedDict(let expectedDict) = expected,
           case .orderedDict(let actualDict) = txBodyPrimitive {
            print("\nDetailed comparison:")
            for (key, expectedValue) in expectedDict {
                if let actualValue = actualDict[key] {
                    if expectedValue != actualValue {
                        print("Key \(key) differs:")
                        print("  Expected: \(expectedValue)")
                        print("  Actual: \(actualValue)")
                    }
                } else {
                    print("Key \(key) missing in actual")
                }
            }
        }
                
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderBurnMultiAsset() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        // Create verification keys from hex data
        let vk1Data = Data(hex: "6443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
        let vk2Data = Data(hex: "6443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
        let vk1 = try VerificationKey(payload: vk1Data)
        let vk2 = try VerificationKey(payload: vk2Data)
        
        let spk1 = NativeScript.scriptPubkey(ScriptPubkey(keyHash: try vk1.hash()))
        let spk2 = NativeScript.scriptPubkey(ScriptPubkey(keyHash: try vk2.hash()))
        let before = NativeScript.invalidHereAfter(AfterScript(slot: 123_456_789))
        let after = NativeScript.invalidBefore(BeforeScript(slot: 123_456_780))
        let innerAll = NativeScript.scriptAll(ScriptAll(scripts: [spk1, spk2]))
        let script = NativeScript.scriptAll(ScriptAll(scripts: [before, after, spk1, innerAll]))
        let policyId = try scriptHash(script: .nativeScript(script))
        
        let toBurn = try MultiAsset(from: [
            policyId.payload.toHex: ["Token1".toData.toHex: -1]
        ])
        let txInput = try TransactionInput(from: .list([
            .bytes(Data(repeating: 0x31, count: 32)),
            .uint(123)
        ]))
        
        let txOut = try TransactionOutput(from: .list([
            .string(sender),
            .list([
                .int(2_000_000),
                .dict([
                    .bytes(policyId.payload): .dict([
                        .string("Token1"): .int(1)
                    ])
                ])
            ])
        ]))
        
        let utxo = UTxO(input: txInput, output: txOut)
        txBuilder.addInput(utxo)
        
        txBuilder.addInputAddress(.string(sender))
        try txBuilder.addOutput(
            TransactionOutput(from: .list([.string(sender), .uint(3000000)]))
        )
        txBuilder.mint = toBurn
        txBuilder.nativeScripts = [script]
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        #expect(txBody.inputs.contains(txInput))
    }
    
    @Test func testTxAddChangeSplitNFTs() async throws {
        let chainContext = MockChainContext()
        let protocolParam = try await chainContext.protocolParameters()
        let newParams = ProtocolParameters(
            collateralPercentage: protocolParam.collateralPercentage,
            coinsPerUtxoWord: protocolParam.coinsPerUtxoWord,
            committeeMaxTermLength: protocolParam.committeeMaxTermLength,
            committeeMinSize: protocolParam.committeeMinSize,
            costModels: protocolParam.costModels,
            dRepActivity: protocolParam.dRepActivity,
            dRepDeposit: protocolParam.dRepDeposit,
            dRepVotingThresholds: protocolParam.dRepVotingThresholds,
            executionUnitPrices: protocolParam.executionUnitPrices,
            govActionDeposit: protocolParam.govActionDeposit,
            govActionLifetime: protocolParam.govActionLifetime,
            maxBlockBodySize: protocolParam.maxBlockBodySize,
            maxBlockExecutionUnits: protocolParam.maxBlockExecutionUnits,
            maxBlockHeaderSize: protocolParam.maxBlockHeaderSize,
            maxCollateralInputs: protocolParam.maxCollateralInputs,
            maxTxExecutionUnits: protocolParam.maxTxExecutionUnits,
            maxTxSize: protocolParam.maxTxSize,
            maxValueSize: 50,
            maxReferenceScriptsSize: protocolParam.maxReferenceScriptsSize,
            minFeeReferenceScripts: protocolParam.minFeeReferenceScripts,
            minFeeRefScriptCostPerByte: protocolParam.minFeeRefScriptCostPerByte,
            minPoolCost: protocolParam.minPoolCost,
            monetaryExpansion: protocolParam.monetaryExpansion,
            poolPledgeInfluence: protocolParam.poolPledgeInfluence,
            poolRetireMaxEpoch: protocolParam.poolRetireMaxEpoch,
            poolVotingThresholds: protocolParam.poolVotingThresholds,
            protocolVersion: protocolParam.protocolVersion,
            stakeAddressDeposit: protocolParam.stakeAddressDeposit,
            stakePoolDeposit: protocolParam.stakePoolDeposit,
            stakePoolTargetNum: protocolParam.stakePoolTargetNum,
            treasuryCut: protocolParam.treasuryCut,
            txFeeFixed: protocolParam.txFeeFixed,
            txFeePerByte: protocolParam.txFeePerByte,
            utxoCostPerByte: protocolParam.utxoCostPerByte
        )
        chainContext._protocolParameters = newParams

        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))

        txBuilder.addInputAddress(.string(sender))
        try txBuilder.addOutput(
            TransactionOutput(address: senderAddress, amount: Value(coin: 7_000_000))
        )

        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ]),
                    .list([
                        .bytes(Data(repeating: 0x32, count: 32)),
                        .uint(1)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(7_000_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(1_034_400),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token1".toData): .int(1),
                            ])
                        ])
                    ])
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(2_793_103),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token2".toData): .int(2),
                            ])
                        ])
                    ])
                ])
            ]),
            .uint(2): .uint(172_497)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
                
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxAddChangeSplitNFTsNotEnough() async throws {
        let chainContext = MockChainContext()
        let protocolParam = try await chainContext.protocolParameters()
        let newParams = ProtocolParameters(
            collateralPercentage: protocolParam.collateralPercentage,
            coinsPerUtxoWord: protocolParam.coinsPerUtxoWord,
            committeeMaxTermLength: protocolParam.committeeMaxTermLength,
            committeeMinSize: protocolParam.committeeMinSize,
            costModels: protocolParam.costModels,
            dRepActivity: protocolParam.dRepActivity,
            dRepDeposit: protocolParam.dRepDeposit,
            dRepVotingThresholds: protocolParam.dRepVotingThresholds,
            executionUnitPrices: protocolParam.executionUnitPrices,
            govActionDeposit: protocolParam.govActionDeposit,
            govActionLifetime: protocolParam.govActionLifetime,
            maxBlockBodySize: protocolParam.maxBlockBodySize,
            maxBlockExecutionUnits: protocolParam.maxBlockExecutionUnits,
            maxBlockHeaderSize: protocolParam.maxBlockHeaderSize,
            maxCollateralInputs: protocolParam.maxCollateralInputs,
            maxTxExecutionUnits: protocolParam.maxTxExecutionUnits,
            maxTxSize: protocolParam.maxTxSize,
            maxValueSize: 50,
            maxReferenceScriptsSize: protocolParam.maxReferenceScriptsSize,
            minFeeReferenceScripts: protocolParam.minFeeReferenceScripts,
            minFeeRefScriptCostPerByte: protocolParam.minFeeRefScriptCostPerByte,
            minPoolCost: protocolParam.minPoolCost,
            monetaryExpansion: protocolParam.monetaryExpansion,
            poolPledgeInfluence: protocolParam.poolPledgeInfluence,
            poolRetireMaxEpoch: protocolParam.poolRetireMaxEpoch,
            poolVotingThresholds: protocolParam.poolVotingThresholds,
            protocolVersion: protocolParam.protocolVersion,
            stakeAddressDeposit: protocolParam.stakeAddressDeposit,
            stakePoolDeposit: protocolParam.stakePoolDeposit,
            stakePoolTargetNum: protocolParam.stakePoolTargetNum,
            treasuryCut: protocolParam.treasuryCut,
            txFeeFixed: protocolParam.txFeeFixed,
            txFeePerByte: protocolParam.txFeePerByte,
            utxoCostPerByte: protocolParam.utxoCostPerByte
        )
        chainContext._protocolParameters = newParams
        
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))

        // Create verification keys from hex data
        let vk1Data = Data(hex: "6443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473")
        let vk2Data = Data(hex: "6443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58475")
        let vk1 = try VerificationKey(payload: vk1Data)
        let vk2 = try VerificationKey(payload: vk2Data)

        let spk1 = NativeScript.scriptPubkey(ScriptPubkey(keyHash: try vk1.hash()))
        let spk2 = NativeScript.scriptPubkey(ScriptPubkey(keyHash: try vk2.hash()))
        let before = NativeScript.invalidHereAfter(AfterScript(slot: 123456789))
        let after = NativeScript.invalidBefore(BeforeScript(slot: 123456780))
        let innerAll = NativeScript.scriptAll(ScriptAll(scripts: [spk1, spk2]))
        let script = NativeScript.scriptAll(ScriptAll(scripts: [before, after, spk1, innerAll]))
        let policyId = try scriptHash(script: .nativeScript(script))

        let mint = try MultiAsset(from: [
            policyId.payload.toHex: ["Token3": 1]
        ])
        
        txBuilder.addInputAddress(.string(sender))
        try txBuilder.addOutput(
            TransactionOutput(from: .list([.string(sender), .uint(8_000_000)]))
        )
        txBuilder.mint = mint
        txBuilder.nativeScripts = [script]
        txBuilder.ttl = 123456789

        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.build(changeAddress: senderAddress)
        }
    }
    
    @Test func testNotEnoughInputAmount() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        let inputUtxo = try await chainContext.utxos(address: senderAddress)[0]

        try txBuilder
            .addInput(inputUtxo)
            .addOutput(TransactionOutput(
                address: senderAddress,
                amount: inputUtxo.output.amount
            ))

        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.build(changeAddress: senderAddress)
        }
    }
    
    @Test func testAddScriptInput() async throws {
        // Create a script-compatible MockChainContext
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)

        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHashValue = try scriptHash(script: .plutusV1Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHashValue),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let txOut1 = TransactionOutput(
            address: scriptAddress,
            amount: Value(coin: 10_000_000),
            datumHash: try datum.hash()
        )
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        let mint = try MultiAsset(from: [
            scriptHashValue.payload.toHex: ["TestToken".toData.toHex: 1]
        ])
        
        let redeemer1 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        let redeemer2 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 5_000_000, steps: 1_000_000)
        )
        
        txBuilder.mint = mint
        
        try await txBuilder.addScriptInput(
            utxo1,
            script: .script(.plutusV1Script(plutusScript)),
            datum: .plutusData(datum),
            redeemer: redeemer1
        )
        
        try txBuilder.addMintingScript(
            .script(.plutusV1Script(plutusScript)),
            redeemer: redeemer2
        )

        let receiver = try Address(from: .string(sender))
        try txBuilder.addOutput(
            TransactionOutput(
                address: receiver,
                amount: Value(coin: 5_000_000)
            )
        )

        _ = try await txBuilder.build(changeAddress: receiver)
        txBuilder.useRedeemerMap = false
        
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedDatum: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([datum])
        )
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.spend,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
            ),
            Redeemer(
                tag: RedeemerTag.mint,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 5_000_000, steps: 1_000_000)
            )
        ])
        let expectedPlutusV1Script: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([plutusScript])
        )
        
        #expect(expectedDatum == witnesses.plutusData)
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(expectedPlutusV1Script == witnesses.plutusV1Script)
        
        let _ = try TransactionWitnessSet.fromCBORHex(witnesses.toCBORHex())
    }
    
    @Test func testAddScriptInputNoScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(
            from: .list([
                .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(0)
            ])
        )
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash(),
                script: .plutusV1Script(plutusScript)
            )
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                datum: .plutusData(datum),
                redeemer: redeemer
            )

        let receiver = try Address(from: .string(sender))
        
        try txBuilder
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000)
                )
            )
        
        let _ = try await txBuilder.build(changeAddress: receiver)
        
        txBuilder.useRedeemerMap = false
        
        let witnesses = try txBuilder.buildWitnessSet(removeDupScript: true)
        
        let expectedDatum: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([datum])
        )
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.spend,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
            )
        ])
        
        #expect(expectedDatum == witnesses.plutusData)
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(witnesses.plutusV1Script == nil)
    }
    
    @Test func testAddScriptInputPaymentScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(
            from: .list([
                .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(0)
            ])
        )

        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let vk1 = try VerificationKey.fromCBORHex(
                "58206443a101bdb948366fc87369336224595d36d8b0eee5602cba8b81a024e58473"
            )
        let scriptAddress = try Address(
            paymentPart: .verificationKeyHash(vk1.hash()),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let txOut1 = TransactionOutput(
            address: scriptAddress,
            amount: Value(coin: 10_000_000),
            datumHash: try datum.hash()
        )
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )

        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder
                .addScriptInput(
                    utxo1,
                    script: .script(.plutusV1Script(plutusScript)),
                    datum: .plutusData(try Unit().toPlutusData()),
                    redeemer: redeemer
                )
        }
    }
    
    @Test func testAddScriptInputFindScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let senderAddress = try Address(from: .string(sender))
        let originalUtxos = try await chainContext.utxos(address: senderAddress)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV1Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        // Create a UTxO that contains the required script (this will be used as reference)
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV1Script(plutusScript)
            )
        )
        
        chainContext._utxos = originalUtxos + [existingScriptUtxo]
        
        // Create redeemer
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        // Add script input without providing script (should find it automatically)
        try await txBuilder.addScriptInput(
            utxo1,
            script: nil, // No script provided - should find from potential inputs
            datum: .plutusData(datum),
            redeemer: redeemer
        )
        
        // Add receiver output
        let receiver = try Address(from: .string(sender))
        try txBuilder.addOutput(
            TransactionOutput(address: receiver, amount: Value(coin: 5_000_000))
        )
        
        // Build transaction
        let txBody = try await txBuilder.build(changeAddress: receiver)
        
        // Build witness set
        let witness = try txBuilder.buildWitnessSet()
        
        // Verify results - script should be found and used as reference
        #expect(witness.plutusData?.count == 1)
        if case .nonEmptyOrderedSet(let plutusDataSet) = witness.plutusData {
            let firstPlutusData = plutusDataSet.elements.first
            #expect(firstPlutusData == datum)
        }
        
        // Check redeemers are present
        #expect(witness.redeemers != nil)
        if case .list(let redeemers) = witness.redeemers {
            #expect(redeemers.count == 1)
        } else if case .map(let redeemersMap) = witness.redeemers {
            #expect(redeemersMap.count == 1)
        }
        
        // Script should NOT be in witness set (it's referenced, not embedded)
        #expect(witness.plutusV1Script == nil)
        
        // The script UTxO should be in reference inputs
        #expect(txBody.referenceInputs?.count == 1)
        #expect(txBody.referenceInputs?.contains(existingScriptUtxo.input) == true)
    }
    
    @Test func testAddScriptInputWithScriptFromSpecifiedUtxo() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))
        
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        // SCENARIO 1: UTxO with incorrect script type
        // Create a UTxO that contains PlutusV1Script (incorrect) instead of required PlutusV2Script
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV2Script(plutusScript)
            )
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        try await txBuilder.addScriptInput(
            utxo1,
            script: .utxo(existingScriptUtxo), // Pass UTxO with correct script
            datum: .plutusData(datum),
            redeemer: redeemer
        )
        
        let receiver = try Address(from: .string(sender))
        try txBuilder.addOutput(
            TransactionOutput(address: receiver, amount: Value(coin: 5_000_000))
        )
        
        let txBody = try await txBuilder.build(changeAddress: receiver)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedDatum: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([datum])
        )
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.spend,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
            )
        ])
        
        #expect(expectedDatum == witnesses.plutusData)
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(witnesses.plutusV2Script == nil)
        #expect(txBody.referenceInputs?.count == 1)
        #expect(txBody.referenceInputs?.contains(existingScriptUtxo.input) == true)
    }
    
    @Test func testAddScriptInputIncorrectScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV1Script(plutusScript))
        let incorrectPlutusScript = PlutusV2Script(data: Data("dummy test script2".utf8))
        
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.addScriptInput(
                utxo1,
                script: .script(.plutusV2Script(incorrectPlutusScript)),
                datum: .plutusData(datum),
                redeemer: redeemer
            )
        }
    }
    
    @Test func testAddScriptInputNoScriptNoAttachedScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV1Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.addScriptInput(
                utxo1,
                script: nil,  // No script provided
                datum: .plutusData(datum),
                redeemer: redeemer
            )
        }
    }
    
    @Test func testAddScriptInputFindIncorrectScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let senderAddress = try Address(from: .string(sender))
        let originalUtxos = try await chainContext.utxos(address: senderAddress)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV1Script(plutusScript))
        
        let incorrectPlutusScript = PlutusV2Script(data: Data("dummy test script2".utf8))
        
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: NetworkId.testnet
        )
        
        let datum = try Unit().toPlutusData()
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV2Script(incorrectPlutusScript)  // INCORRECT script type
            )
        )
        
        chainContext._utxos = originalUtxos + [existingScriptUtxo]
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.addScriptInput(
                utxo1,
                script: nil, // No script provided - should try to find automatically but fail
                datum: .plutusData(datum),
                redeemer: redeemer
            )
        }
    }
    
    @Test func testAddScriptInputWithScriptFromSpecifiedUtxoWithIncorrectScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))
        
        let incorrectPlutusScript = PlutusV1Script(data: Data("dummy test script2".utf8))
        
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let existingScriptUtxoWithIncorrectScript = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV1Script(incorrectPlutusScript)  // INCORRECT script type
            )
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.addScriptInput(
                utxo1,
                script: .utxo(existingScriptUtxoWithIncorrectScript), // Pass UTxO with incorrect script
                datum: .plutusData(datum),
                redeemer: redeemer
            )
        }
        
        let existingScriptUtxoWithNoScript = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567)
                // No script attached to this UTxO
            )
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.addScriptInput(
                utxo1,
                script: .utxo(existingScriptUtxoWithNoScript), // Pass UTxO with no script
                datum: .plutusData(datum),
                redeemer: redeemer
            )
        }
    }
    
    @Test func testAddScriptInputMultipleRedeemers() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        let txIn2 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(1)
        ]))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        let utxo2 = UTxO(
            input: txIn2,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV2Script(plutusScript)
            )
        )
        
        let redeemer1 = Redeemer(
            data: try Unit().toPlutusData()
        )
        let redeemer2 = Redeemer(
            data: try Unit().toPlutusData()
        )
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                script: .utxo(existingScriptUtxo),
                datum: .plutusData(datum),
                redeemer: redeemer1
            )
            .addScriptInput(
                utxo2,
                script: .utxo(existingScriptUtxo),
                datum: .plutusData(datum),
                redeemer: redeemer2
            )
        
        let redeemerWithExUnits = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder.addScriptInput(
                utxo2, // Same UTxO as before
                script: .utxo(existingScriptUtxo),
                datum: .plutusData(datum),
                redeemer: redeemerWithExUnits
            )
        }
        
        let txBuilder2 = TxBuilder(context: chainContext)
        
        let redeemerWithExUnits1 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        let redeemerWithExUnits2 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        try await txBuilder2
            .addScriptInput(
                utxo1,
                script: .utxo(existingScriptUtxo),
                datum: .plutusData(datum),
                redeemer: redeemerWithExUnits1
            )
            .addScriptInput(
                utxo2,
                script: .utxo(existingScriptUtxo),
                datum: .plutusData(datum),
                redeemer: redeemerWithExUnits2
            )
        
        let redeemerDefault = Redeemer(
            data: try Unit().toPlutusData()
            // No execution units - default
        )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder2.addScriptInput(
                utxo2,
                script: .utxo(existingScriptUtxo),
                datum: .plutusData(datum),
                redeemer: redeemerDefault
            )
        }
    }
    
    @Test func testAddMintingScriptFromSpecifiedUtxo() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV2Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV2Script(plutusScript)
            )
        )
        
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        try txBuilder
            .addMintingScript(
                .utxo(existingScriptUtxo),
                redeemer: redeemer
            )

        let receiver = try Address(from: .string(sender))
        
        try txBuilder
            .addInputAddress(.address(receiver))
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_00)
                )
            )
        
        txBuilder.mint = mint
        let txBody = try await txBuilder.build(changeAddress: receiver)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.mint,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
            )
        ])
        
        #expect(witnesses.plutusData == nil)
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(witnesses.plutusV2Script == nil)
        #expect(txBody.referenceInputs?.count == 1)
        #expect(txBody.referenceInputs?.contains(existingScriptUtxo.input) == true)
    }
    
    @Test func testCollateralReturn() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let senderAddress = try Address(from: .string(sender))
        var originalUtxos = try await chainContext.utxos(address: senderAddress)

        let txIn1 = try TransactionInput(
            transactionId: TransactionId(from: .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef")),
            index: 0
        )
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()

        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV1Script(plutusScript)
            )
        )
        
        originalUtxos[0].output.amount.multiAsset = try MultiAsset(from: [
            Data(repeating: 0x31, count: 28).toHex: [
                "Token1".toData.toHex: 1,
                "Token2".toData.toHex:2,
            ]
        ])
        chainContext._utxos = originalUtxos + [existingScriptUtxo]

        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        let receiver = try Address(from: .string(sender))
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                datum: .plutusData(datum),
                redeemer: redeemer
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000)
                )
            )

        let txBody = try await txBuilder.build(changeAddress: receiver)

        #expect(txBody.collateralReturn?.address == receiver)
        #expect(
            txBody.collateralReturn!.amount + Value(coin: Int(txBody.totalCollateral!))  == originalUtxos[0].output.amount
        )
    }
    
    @Test(arguments: [
        (Value(coin: 4_000_000), 0, false),
        (Value(coin: 4_000_000), 1_000_000, false),
        (Value(coin: 6_000_000), 2_000_000, true),
        (Value(coin: 6_000_000), 3_000_000, false),
        (
            Value(
                coin: 6_000_000,
                multiAsset: try MultiAsset(from: [
                    Data(repeating: 0x31, count: 28).toHex: [
                        "Token1".toData.toHex: 1,
                        "Token2".toData.toHex:2,
                    ]
                ]),
            ),
            3_000_000,
            true
        ),
    ]) func testNoCollateralReturn(testInput: (SwiftCardanoCore.Value, Int, Bool)) async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(
            context: chainContext,
            collateralReturnThreshold: testInput.1
        )
        
        let senderAddress = try Address(from: .string(sender))
        var originalUtxos = try await chainContext.utxos(address: senderAddress)

        let txIn1 = try TransactionInput(
            transactionId: TransactionId(from: .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef")),
            index: 0
        )
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()

        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV1Script(plutusScript)
            )
        )
        
        originalUtxos[0].output.amount = testInput.0
        chainContext._utxos = Array(originalUtxos.prefix(1)) + [existingScriptUtxo]

        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        let receiver = try Address(from: .string(sender))
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                datum: .plutusData(datum),
                redeemer: redeemer
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000)
                )
            )

        let txBody = try await txBuilder.build(changeAddress: receiver)

        #expect((txBody.collateralReturn != nil) == testInput.2)
        #expect((txBody.totalCollateral != nil) == testInput.2)
    }
    
    @Test func testCollateralReturnMinReturnAmount() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let senderAddress = try Address(from: .string(sender))
        var originalUtxos = try await chainContext.utxos(address: senderAddress)

        let txIn1 = try TransactionInput(
            transactionId: TransactionId(from: .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef")),
            index: 0
        )
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()

        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV1Script(plutusScript)
            )
        )
        
        originalUtxos[0].output.amount.multiAsset = try MultiAsset(from: [
            Data(repeating: 0x31, count: 28).toHex: Dictionary(
                uniqueKeysWithValues: (0..<500).map { i in
                    let tokenName = "Token".data(using: .utf8)! + withUnsafeBytes(of: i.bigEndian) { Data($0.suffix(10)) }
                    return (tokenName.toHex, i)
                }
            )
        ])
        originalUtxos[0].output.amount.coin = try await Int(
            minLovelacePostAlonzo(
                originalUtxos[0].output,
                chainContext
            )
        )
        chainContext._utxos = originalUtxos + [existingScriptUtxo]

        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        let receiver = try Address(from: .string(sender))
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                datum: .plutusData(datum),
                redeemer: redeemer
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000)
                )
            )

        let txBody = try await txBuilder.build(changeAddress: receiver)
        
        let expectedMinCollateralReturnAmount: Int = try await Int(
            minLovelacePostAlonzo(
                originalUtxos[0].output,
                chainContext
            )
        )

        #expect(txBody.collateralReturn?.address == receiver)
        #expect(
            txBody.collateralReturn!.amount.coin >= expectedMinCollateralReturnAmount
        )
    }
    
    @Test func testWrongRedeemerExecutionUnits() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        
        let redeemer1 = Redeemer(
            data: try Unit().toPlutusData()
        )
        let redeemer2 = Redeemer(
            data: try Unit().toPlutusData()
        )
        let redeemer3 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        txBuilder.mint = mint
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                script: .script(.plutusV2Script(plutusScript)),
                datum: .plutusData(datum),
                redeemer: redeemer1
            )
            .addMintingScript(
                .script(.plutusV2Script(plutusScript)),
                redeemer: redeemer2
            )
        
        #expect(throws: CardanoTxBuilderError.self) {
            let _ = try txBuilder
                .addMintingScript(
                    .script(.plutusV2Script(plutusScript)),
                    redeemer: redeemer3
                )
        }
        
    }
    
    @Test func testAllRedeemerShouldProvideExecutionUnits() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        
        let redeemer1 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        let redeemer2 = Redeemer(
            data: try Unit().toPlutusData()
        )
        
        txBuilder.mint = mint
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                script: .script(.plutusV2Script(plutusScript)),
                datum: .plutusData(datum),
                redeemer: redeemer1
            )
        
        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder
                .addScriptInput(
                    utxo1,
                    script: .script(.plutusV2Script(plutusScript)),
                    datum: .plutusData(datum),
                    redeemer: redeemer2
                )
        }
        
    }
    
    @Test func testAddMintingScript() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(
            transactionId: TransactionId(from: .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef")),
            index: 0
        )
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        let receiver = try Address(from: .string(sender))
        
        txBuilder.mint = mint
        
        try txBuilder
            .addInput(utxo1)
            .addMintingScript(
                .script(.plutusV1Script(plutusScript)),
                redeemer: redeemer
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000, multiAsset: mint)
                )
            )
        
        _ = try await txBuilder.build(changeAddress: receiver)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedPlutusV1Script: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([
                plutusScript
            ])
        )
        
        #expect(expectedPlutusV1Script == witnesses.plutusV1Script)
    }
    
    @Test func testAddMintingScriptOnly() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(
            transactionId: TransactionId(from: .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef")),
            index: 0
        )
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        
        let receiver = try Address(from: .string(sender))
        
        txBuilder.mint = mint
        
        try txBuilder
            .addInput(utxo1)
            .addMintingScript(
                .script(.plutusV1Script(plutusScript))
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000, multiAsset: mint)
                )
            )
        
        _ = try await txBuilder.build(changeAddress: receiver)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedPlutusV1Script: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([
                plutusScript
            ])
        )
        
        #expect(expectedPlutusV1Script == witnesses.plutusV1Script)
    }
    
    @Test func testAddMintingScriptWrongRedeemerType() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        
        let redeemer = Redeemer(
            tag: .spend, // Wrong tag for minting
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000),
        )
        
        #expect(throws: CardanoTxBuilderError.self) {
            let _ = try txBuilder
                .addMintingScript(
                    .script(.plutusV1Script(plutusScript)),
                    redeemer: redeemer
                )
        }
    }
    
    @Test func testExcludedInput() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0, 0, 0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))

        try txBuilder
            .addInputAddress(.address(senderAddress))
            .addOutput(
                try TransactionOutput(from: .list([.string(sender), .uint(500_000)]))
            )

        let utxos = try await chainContext.utxos(address: senderAddress)
        txBuilder.excludedInputs.append(utxos[0])

        let txBody = try await txBuilder.build(changeAddress: senderAddress)

        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x32, count: 32)),
                        .uint(1)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(500_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .list([
                        .int(5_332_167),
                        .orderedDict([
                            .bytes(Data(repeating: 0x31, count: 28)): .orderedDict([
                                .bytes("Token1".toData): .int(1),
                                .bytes("Token2".toData): .int(2)
                            ])
                        ])
                    ])
                ])
            ]),
            .uint(2): .uint(167_833)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testBuildAndSign() async throws {
        let chainContext = MockChainContext()
        let senderAddress = try Address(from: .string(sender))
        var sequence: [Int] = [0, 0, 0, 0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        let txBuilder1 = TxBuilder(context: chainContext, utxoSelectors: [selector])
        txBuilder1.addInputAddress(.address(senderAddress))
        try txBuilder1.addOutput(
            try TransactionOutput(from: .list([.string(sender), .uint(500000)]))
        )

        let txBody = try await txBuilder1.build(changeAddress: senderAddress)

        let txBuilder2 = TxBuilder(context: chainContext, utxoSelectors: [selector])
        txBuilder2.addInputAddress(.address(senderAddress))
        try txBuilder2.addOutput(
            try TransactionOutput(from: .list([.string(sender), .uint(500000)]))
        )

        let tx = try await txBuilder2.buildAndSign(
            signingKeys: [.signingKey(paymentSigningKey!)],
            changeAddress: senderAddress,
            forceSkeys: true
        )
        
        let vkeyWitnesses: ListOrNonEmptyOrderedSet<VerificationKeyWitness> = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([
                VerificationKeyWitness(
                    vkey: .verificationKey(try VerificationKey(from: .bytes(paymentVerificationKey!.toBytes()))),
                    signature: try paymentSigningKey!.sign(data: txBody.hash())
                )
            ])
        )
        
        let txBodyCBORHex = try tx.transactionBody.toCBORHex()

        #expect(tx.transactionWitnessSet.vkeyWitnesses == vkeyWitnesses)
        #expect(txBodyCBORHex == "a300d9010281825820313131313131313131313131313131313131313131313131313131313131313100018282581d60f6532850e1bccee9c72a9113ad98bcc5dbb30d2ac960262444f6e5f41a0007a12082581d60f6532850e1bccee9c72a9113ad98bcc5dbb30d2ac960262444f6e5f41a004222f3021a0002872d")
    }
    
    @Test func testEstimateExecutionUnit() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let datum = try Unit().toPlutusData()
        
        let txIn1 = try TransactionInput(from: .list([
            .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
            .uint(0)
        ]))
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData()
        )
        
        let receiver = try Address(from: .string(sender))
        
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        
        txBuilder.mint = mint
        
        try await txBuilder
            .addInputAddress(.string(sender))
            .addScriptInput(
                utxo1,
                script: .script(.plutusV1Script(plutusScript)),
                datum: .plutusData(datum),
                redeemer: redeemer
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000)
                )
            )
        _ = try await txBuilder.build(changeAddress: receiver)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedDatum: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([datum])
        )
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.spend,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 479858, steps: 211128864)
            )
        
        ])
        let expectedPlutusV1Script: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([plutusScript])
        )
        
        #expect(expectedDatum == witnesses.plutusData)
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(expectedPlutusV1Script == witnesses.plutusV1Script)
    }
    
    @Test func testAddScriptInputInlineDatumExtra() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(
            from: .list([
                .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(0)
            ])
        )

        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(script: .plutusV1Script(plutusScript))
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let txOut1 = TransactionOutput(
            address: scriptAddress,
            amount: Value(coin: 10_000_000),
            datumOption: DatumOption(datum: datum)
        )
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )

        await #expect(throws: CardanoTxBuilderError.self) {
            let _ = try await txBuilder
                .addScriptInput(
                    utxo1,
                    script: .script(.plutusV1Script(plutusScript)),
                    datum: .plutusData(try Unit().toPlutusData()),
                    redeemer: redeemer
                )
        }
    }
    
    @Test func testTxBuilderExactFeeNoChange() async throws {
        let chainContext = MockChainContext()
        let txBuilder1 = TxBuilder(context: chainContext)
        let txBuilder2 = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let inputAmount = 10_000_000
        
        let txIn1 = try TransactionInput(from: .list([
            .bytes(Data(repeating: 0x31, count: 32)),
            .uint(3)
        ]))
        let txOut1 = try TransactionOutput(from: .list([
            .string(sender),
            .uint(UInt(inputAmount))
        ]))
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        try txBuilder1
            .addInput(utxo1)
            .addOutput(
                TransactionOutput(from: .list([.string(sender), .uint(5_000_000)]))
            )
        
        let txBody = try await txBuilder1.build()
        
        let txIn2 = try TransactionInput(from: .list([
            .bytes(Data(repeating: 0x31, count: 32)),
            .uint(3)
        ]))
        let txOut2 = try TransactionOutput(from: .list([
            .string(sender),
            .uint(UInt(inputAmount))
        ]))
        let utxo2 = UTxO(input: txIn2, output: txOut2)
        
        try txBuilder2
            .addInput(utxo2)
            .addOutput(
                TransactionOutput(from: .list([.string(sender), .uint(UInt(inputAmount - Int(txBody.fee)))]))
            )
        
        let tx = try await txBuilder2.buildAndSign(
            signingKeys: [.signingKey(paymentSigningKey!)]
        )
            
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(9_835_951)
                ])
            ]),
            .uint(2): .uint(164_049)
        ])
        
        let txBodyPrimitive = try tx.transactionBody.toPrimitive()
        
        let expectedFee = try await calculateFee(
            chainContext,
            length: UInt64(try tx.toCBORData().count)
        )
        
        #expect(expected == txBodyPrimitive)
        #expect(tx.transactionBody.fee >= expectedFee)
    }
    
    @Test func testTxBuilderCertificates() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        let stakeKeyHash = VerificationKeyHash(payload: Data(repeating: 0x31, count: 28))
        let stakeCredential = StakeCredential(credential: .verificationKeyHash(stakeKeyHash))
        let poolHash = PoolKeyHash(payload: Data(repeating: 0x31, count: 28))
        
        let stakeRegistration = StakeRegistration(stakeCredential: stakeCredential)
        let stakeDelegation = StakeDelegation(stakeCredential: stakeCredential, poolKeyHash: poolHash)
        
        try txBuilder
            .addInputAddress(.string(sender))
            .addOutput(
                try TransactionOutput(from: .list([.string(sender), .uint(500_000)]))
            )
        
        txBuilder.certificates = [
            .stakeRegistration(stakeRegistration),
            .stakeDelegation(stakeDelegation)
        ]
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(500_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .int(2_325_479)
                ])
            ]),
            .uint(2): .uint(174_521),
            .uint(4): .list([
                .list([
                    .uint(0),
                    .list([
                        .uint(0),
                        .bytes(Data(repeating: 0x31, count: 28)),
                    ])
                ]),
                .list([
                    .uint(2),
                    .list([
                        .uint(0),
                        .bytes(Data(repeating: 0x31, count: 28)),
                    ]),
                    .bytes(Data(repeating: 0x31, count: 28))
                ])
            ]),
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderCertificatesScript() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV2Script(plutusScript)
        )
        
        let stakeCredential = StakeCredential(
            credential: .scriptHash(scriptHash)
        )
        let poolHash = PoolKeyHash(payload: Data(repeating: 0x31, count: 28))

        let stakeRegistration = StakeRegistration(stakeCredential: stakeCredential)
        let stakeDelegation = StakeDelegation(stakeCredential: stakeCredential, poolKeyHash: poolHash)

        try txBuilder
            .addInputAddress(.string(sender))
            .addOutput(
                try TransactionOutput(from: .list([.string(sender), .uint(500_000)]))
            )
        
        txBuilder.certificates = [
            .stakeRegistration(stakeRegistration),
            .stakeDelegation(stakeDelegation)
        ]
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 100_000, steps: 1_000_000)
        )
        
        try txBuilder.addCertificateScript(
            .script(.plutusV2Script(plutusScript)),
            redeemer: redeemer
        )
        
        txBuilder.ttl = 123456

        _ = try await txBuilder.build(changeAddress: senderAddress)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.cert,
                index: 1,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 100_000, steps: 1_000_000)
            )
        ])
        let expectedPlutusV2Script: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([
                plutusScript
            ])
        )
        
        guard case let .list(redeemersList) = witnesses.redeemers else {
            Issue.record("Unexpected witness redeemers format")
            return
        }
        
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(redeemersList[0].index == 1)
        #expect(expectedPlutusV2Script == witnesses.plutusV2Script)
    }
    
    @Test func testTxBuilderCertRedeemerWrongTag() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        
        let redeemer = Redeemer(
            tag: .mint, // Wrong tag for certificate
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 100_000, steps: 1_000_000)
        )
        
        #expect(throws: CardanoTxBuilderError.self) {
            let _ = try txBuilder.addCertificateScript(
                .script(.plutusV2Script(plutusScript)),
                redeemer: redeemer
            )
        }
    }
    
    @Test func testAddCertScriptFromUTxO() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let plutusScript = PlutusV2Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV2Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        
        let existingScriptUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 1_234_567),
                script: .plutusV2Script(plutusScript)
            )
        )
        
        let stakeCredential = StakeCredential(
            credential: .scriptHash(scriptHash)
        )
        let poolHash = PoolKeyHash(payload: Data(repeating: 0x31, count: 28))

        let stakeRegistration = StakeRegistration(stakeCredential: stakeCredential)
        let stakeDelegation = StakeDelegation(stakeCredential: stakeCredential, poolKeyHash: poolHash)

        try txBuilder
            .addInputAddress(.string(sender))
            .addOutput(
                try TransactionOutput(from: .list([.string(sender), .uint(500_000)]))
            )
        
        txBuilder.certificates = [
            .stakeRegistration(stakeRegistration),
            .stakeDelegation(stakeDelegation)
        ]
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 100_000, steps: 1_000_000)
        )
        
        try txBuilder.addCertificateScript(
            .utxo(existingScriptUtxo),
            redeemer: redeemer
        )
        
        txBuilder.ttl = 123456

        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        txBuilder.useRedeemerMap = false
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedRedeemers: Redeemers = .list([
            Redeemer(
                tag: RedeemerTag.cert,
                index: 1,
                data: try Unit().toPlutusData(),
                exUnits: ExecutionUnits(mem: 100_000, steps: 1_000_000)
            )
        ])
        
        let expectedReferenceInputs: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([
                existingScriptUtxo.input
            ])
        )
        
        #expect(expectedRedeemers == witnesses.redeemers)
        #expect(witnesses.plutusV2Script == nil)
        #expect(expectedReferenceInputs == txBody.referenceInputs)
    }
    
    @Test func testTxBuilderStakePoolRegistration() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        
        let poolRegistration = PoolRegistration(poolParams: poolParams)
        
        let txIn = try TransactionInput(from: .list([
            .bytes(Data(repeating: 0x32, count: 32)),
            .uint(2)
        ]))
        let txOut = try TransactionOutput(from: .list([
            .string(sender),
            .uint(505_000_000)
        ]))
        let utxo = UTxO(input: txIn, output: txOut)
        
        txBuilder.addInput(utxo)
        
        txBuilder.initialStakePoolRegistration = true
        
        txBuilder.certificates = [
            .poolRegistration(poolRegistration)
        ]
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x32, count: 32)),
                        .uint(2)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    .bytes(Data([
                        0x60, 0xf6, 0x53, 0x28, 0x50, 0xe1, 0xbc, 0xce,
                        0xe9, 0xc7, 0x2a, 0x91, 0x13, 0xad, 0x98, 0xbc,
                        0xc5, 0xdb, 0xb3, 0x0d, 0x2a, 0xc9, 0x60, 0x26,
                        0x24, 0x44, 0xf6, 0xe5, 0xf4
                    ])),
                    .int(4_819_143)
                ])
            ]),
            .uint(2): .uint(180_857),
            .uint(4): .list([
                .list([
                    .uint(3),
                    .bytes(Data(repeating: 0x31, count: POOL_KEY_HASH_SIZE)),
                    .bytes(Data(repeating: 0x31, count: VRF_KEY_HASH_SIZE)),
                    .int(100000000),
                    .int(340000000),
                    .cborTag(
                        CBORTag(
                            tag: 30,
                            value: .list([
                                .uint(UInt(1)),
                                .uint(UInt(50))
                            ])
                        )
                    ),
                    .bytes(Data(repeating: 0x31, count: REWARD_ACCOUNT_HASH_SIZE)),
                    .list([
                        .bytes(Data(repeating: 0x31, count: VERIFICATION_KEY_HASH_SIZE)),
                    ]),
                    .list([
                        .list([
                            .uint(0),
                            .uint(3001),
                            .bytes(Data([0xC0, 0xA8, 0x00, 0x01])),
                            .bytes(Data([
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                            ])),
                        ]),
                        .list([
                            .uint(1),
                            .uint(3001),
                            .string("relay1.example.com"),
                        ]),
                        .list([
                            .uint(2),
                            .string("relay1.example.com"),
                        ]),
                    ]),
                    .list([
                        .string("https://meta1.example.com"),
                        .bytes(Data(repeating: 0x31, count: POOL_METADATA_HASH_SIZE)),
                    ])
                ])
            ]),
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderWithdrawal() async throws {
        let chainContext = MockChainContext()
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })
        let txBuilder = TxBuilder(context: chainContext, utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))

        let stakeAddress = try Address(
            from: .string("stake_test1upyz3gk6mw5he20apnwfn96cn9rscgvmmsxc9r86dh0k66gswf59n")
        )

        txBuilder.addInputAddress(.string(sender))
        try txBuilder.addOutput(
            try TransactionOutput(from: .list([.string(sender), .uint(500000)]))
        )

        let withdrawals = Withdrawals([
            RewardAccount(stakeAddress.toBytes()): Coin(10_000)
        ])
        txBuilder.withdrawals = withdrawals

        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(0)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(500_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .int(4_338_295)
                ])
            ]),
            .uint(2): .uint(171_705),
            .uint(5): .orderedDict([
                .bytes(Data([
                    0xe0, 0x48, 0x28, 0xa2, 0xda, 0xdb, 0xa9, 0x7c,
                    0xa9, 0xfd, 0x0c, 0xdc, 0x99, 0x97, 0x58, 0x99,
                    0x47, 0x0c, 0x21, 0x9b, 0xdc, 0x0d, 0x82, 0x8c,
                    0xfa, 0x6d, 0xdf, 0x6d, 0x69
                ])): .uint(10_000),
            ])
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderNoOutput() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let inputAmount = 10_000_000
        
        let txIn1 = try TransactionInput(from: .list([
            .bytes(Data(repeating: 0x31, count: 32)),
            .uint(3)
        ]))
        let txOut1 = try TransactionOutput(from: .list([
            .string(sender),
            .uint(UInt(inputAmount))
        ]))
        let utxo1 = UTxO(input: txIn1, output: txOut1)
        
        txBuilder.addInput(utxo1)

        let txBody = try await txBuilder.build(
            changeAddress: senderAddress,
            mergeChange: true
        )

        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(9_835_951)
                ])
            ]),
            .uint(2): .uint(164_049)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderMergeChangeToOutput1() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let inputAmount = 10_000_000

        let txIn = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut = TransactionOutput(address: senderAddress, amount: Value(coin: inputAmount))
        let utxo = UTxO(input: txIn, output: txOut)

        try txBuilder
            .addInput(utxo)
            .addOutput(
                TransactionOutput(address: senderAddress, amount: Value(coin: 10_000))
            )

        let txBody = try await txBuilder.build(
            changeAddress: senderAddress,
            mergeChange: true
        )
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(9_835_951)
                ])
            ]),
            .uint(2): .uint(164_049)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderMergeChangeToOutput2() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let receiver = "addr_test1vr2p8st5t5cxqglyjky7vk98k7jtfhdpvhl4e97cezuhn0cqcexl7"
        let receiverAddress = try Address(from: .string(receiver))
        
        let inputAmount = 10_000_000

        let txIn = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut = TransactionOutput(address: senderAddress, amount: Value(coin: inputAmount))
        let utxo = UTxO(input: txIn, output: txOut)

        try txBuilder
            .addInput(utxo)
            .addOutput(
                TransactionOutput(address: senderAddress, amount: Value(coin: 10_000))
            )
            .addOutput(
                TransactionOutput(address: receiverAddress, amount: Value(coin: 10_000))
            )
            .addOutput(
                TransactionOutput(address: senderAddress, amount: Value(coin: 0))
            )

        let txBody = try await txBuilder.build(
            changeAddress: senderAddress,
            mergeChange: true
        )
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(10_000)
                ]),
                .list([
                    receiverAddress.toPrimitive(),
                    .int(10_000)
                ]),
                .list([
                    senderAddress.toPrimitive(),
                    .int(9_812_871)
                ]),
            ]),
            .uint(2): .uint(167_129)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxMergeChangeToZeroAmountOutput() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let inputAmount = 10_000_000

        let txIn = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut = TransactionOutput(address: senderAddress, amount: Value(coin: inputAmount))
        let utxo = UTxO(input: txIn, output: txOut)

        try txBuilder
            .addInput(utxo)
            .addOutput(
                TransactionOutput(address: senderAddress, amount: Value(coin: 0))
            )

        let txBody = try await txBuilder.build(
            changeAddress: senderAddress,
            mergeChange: true
        )
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(9_835_951)
                ])
            ]),
            .uint(2): .uint(164_049)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxMergeChangeSmallerThanMinUTxO() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let inputAmount = 10_000_000

        let txIn = try TransactionInput(
            from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .uint(3)
            ])
        )
        let txOut = TransactionOutput(address: senderAddress, amount: Value(coin: inputAmount))
        let utxo = UTxO(input: txIn, output: txOut)

        try txBuilder
            .addInput(utxo)
            .addOutput(
                TransactionOutput(address: senderAddress, amount: Value(coin: 9_800_000))
            )

        let txBody = try await txBuilder.build(
            changeAddress: senderAddress,
            mergeChange: true
        )
        
        let expected: Primitive = .orderedDict([
            .uint(0): .orderedSet(
                try OrderedSet([
                    .list([
                        .bytes(Data(repeating: 0x31, count: 32)),
                        .uint(3)
                    ])
                ])
            ),
            .uint(1): .list([
                .list([
                    senderAddress.toPrimitive(),
                    .int(9_835_951)
                ])
            ]),
            .uint(2): .uint(164_049)
        ])
        
        let txBodyPrimitive = try txBody.toPrimitive()
        
        #expect(expected == txBodyPrimitive)
    }
    
    @Test func testTxBuilderSmallUTxOInput1() async throws {
        let utxosToUse = [
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                    .uint(1)
                ])),
                output: TransactionOutput(
                    address: try Address(
                        from: .string(
                            "addr1qytqt3v9ej3kzefxcy8f59h9atf2knracnj5snkgtaea6p4r8g3mu652945v3gldw7v88dn5lrfudx0un540ak9qt2kqhfjl0d"
                        )
                    ),
                    amount: Value(coin: 2_991_353)
                )
            )
        ]
        
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        chainContext._utxos = utxosToUse
        
        let address1 = try Address(
            from: .string(
                "addr1qytqt3v9ej3kzefxcy8f59h9atf2knracnj5snkgtaea6p4r8g3mu652945v3gldw7v88dn5lrfudx0un540ak9qt2kqhfjl0d"
            )
        )
        
        let address2 = try Address(
            from: .string(
                "addr1qyady0evsaxqsfmz0z8rvmq62fmuas5w8n4m8z6qcm4wrt3e8dlsen8n464ucw69acfgdxgguscgfl5we3rwts4s57ashysyee"
            )
        )
        
        try txBuilder
            .addInputAddress(.address(address1))
            .addOutput(
                TransactionOutput(
                    address: address2,
                    amount: Value(coin: 1_000_000)
                )
            )
        
        _ = try await txBuilder.build(changeAddress: address1)
    }
    
    @Test func testTxBuilderSmallUTxOInput2() async throws {
        let utxosToUse = [
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("233a835316f4c27bceafdd190639c9c7b834224a7ab7fce13330495437d977fa"),
                    .uint(0)
                ])),
                output: TransactionOutput(
                    address: try Address(
                        from: .string(
                            "addr1q872eujv4xcuckfarjklttdfep7224gjt7wrxkpu8ve3v6g4x2yx743payyucr327fz0dkdwkj9yc8gemtctgmzpjd8qcdw8qr"
                        )
                    ),
                    amount: Value(coin: 5_639_430)
                )
            ),
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("233a835316f4c27bceafdd190639c9c7b834224a7ab7fce13330495437d977fa"),
                    .uint(1)
                ])),
                output: TransactionOutput(
                    address: try Address(
                        from: .string(
                            "addr1q872eujv4xcuckfarjklttdfep7224gjt7wrxkpu8ve3v6g4x2yx743payyucr327fz0dkdwkj9yc8gemtctgmzpjd8qcdw8qr"
                        )
                    ),
                    amount: Value(
                        coin: 5_639_430,
                        multiAsset: try MultiAsset(from: [
                            "c4d5ae259e40eb7830df9de67b0a6a536b7e3ed645de2a13eedc7ece": ["x your eyes": 1]
                        ])
                    )
                )
            ),
        ]
        
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        chainContext._utxos = utxosToUse
        
        let address1 = try Address(
            from: .string(
                "addr1q872eujv4xcuckfarjklttdfep7224gjt7wrxkpu8ve3v6g4x2yx743payyucr327fz0dkdwkj9yc8gemtctgmzpjd8qcdw8qr"
            )
        )
        
        let address2 = try Address(
            from: .string(
                "addr1qxx7lc2kyrjp4qf3gkpezp24ugu35em2f5h05apejzzy73c7yf794gk9yzhngdse36rae52c7a6rv5seku25cd8ntves7f5fe4"
            )
        )
        
        try txBuilder
            .addInputAddress(.address(address1))
            .addOutput(
                TransactionOutput(
                    address: address2,
                    amount: Value(
                        coin: 3_000_000,
                        multiAsset: try MultiAsset(from: [
                            "c4d5ae259e40eb7830df9de67b0a6a536b7e3ed645de2a13eedc7ece": ["x your eyes": 1]
                        ])
                    )
                )
            )
        
        _ = try await txBuilder.build(changeAddress: address1)
    }
    
    @Test func testTxBuilderSmallUTxOInput3() async throws {
        let address = try Address(
            from: .string(
                "addr1qytqt3v9ej3kzefxcy8f59h9atf2knracnj5snkgtaea6p4r8g3mu652945v3gldw7v88dn5lrfudx0un540ak9qt2kqhfjl0d"
            )
        )
        
        let utxosToUse = [
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7"),
                    .uint(1)
                ])),
                output: TransactionOutput(
                    address: address,
                    amount: Value(coin: 2_991_353)
                )
            )
        ]
        
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        chainContext._utxos = utxosToUse
        
        try txBuilder
            .addInputAddress(.address(address))
            .addOutput(
                TransactionOutput(
                    address: address,
                    amount: Value(
                        coin: 1_000_000
                    )
                )
            )
        
        let tx = try await txBuilder.build(changeAddress: address, mergeChange: true)
        
        #expect(tx.outputs.count == 1)
    }
    
    @Test func testBuildWitnessSetMixedScripts() async throws {
        let plutusV1Script = PlutusV1Script(data: Data("plutus v1 script".utf8))
        let plutusV1ScriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusV1Script)
        )
        let plutusV2Script = PlutusV2Script(data: Data("plutus v2 script".utf8))
        let plutusV2ScriptHash = try plutusScriptHash(
            script: .plutusV2Script(plutusV2Script)
        )
        let plutusV3Script = PlutusV3Script(data: Data("plutus v3 script".utf8))
        let plutusV3ScriptHash = try plutusScriptHash(
            script: .plutusV3Script(plutusV3Script)
        )
        
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let inputV1 = UTxO(
            input: TransactionInput(
                transactionId: TransactionId(payload: Data(repeating: 0, count: 32)),
                index: 0
            ),
            output: TransactionOutput(
                address: try Address(
                    paymentPart: .scriptHash(plutusV1ScriptHash),
                    stakingPart: .none,
                    network: chainContext.networkId
                ),
                amount: Value(coin: 1_000_000),
                script: .plutusV1Script(plutusV1Script)
            )
        )
        
        let inputV2 = UTxO(
            input: TransactionInput(
                transactionId: TransactionId(payload: Data(repeating: 0, count: 32)),
                index: 1
            ),
            output: TransactionOutput(
                address: try Address(
                    paymentPart: .scriptHash(plutusV2ScriptHash),
                    stakingPart: .none,
                    network: chainContext.networkId
                ),
                amount: Value(coin: 1_000_000),
                script: .plutusV2Script(plutusV2Script)
            )
        )

        let inputV3 = UTxO(
            input: TransactionInput(
                transactionId: TransactionId(payload: Data(repeating: 0, count: 32)),
                index: 3
            ),
            output: TransactionOutput(
                address: try Address(
                    paymentPart: .scriptHash(plutusV3ScriptHash),
                    stakingPart: .none,
                    network: chainContext.networkId
                ),
                amount: Value(coin: 1_000_000),
                script: .plutusV3Script(plutusV3Script)
            )
        )
        
        let additionalV1Script = PlutusV1Script(data: Data("additional v1 script".utf8))
        let additionalPlutusV1ScriptHash = try plutusScriptHash(
            script: .plutusV1Script(additionalV1Script)
        )
        
        let inputAdditionalV1 = UTxO(
            input: TransactionInput(
                transactionId: TransactionId(payload: Data(repeating: 0x31, count: 32)),
                index: 0
            ),
            output: TransactionOutput(
                address: try Address(
                    paymentPart: .scriptHash(additionalPlutusV1ScriptHash),
                    stakingPart: .none,
                    network: chainContext.networkId
                ),
                amount: Value(coin: 1_000_000),
                script: .plutusV1Script(additionalV1Script)
            )
        )
        
        txBuilder
            .addInput(inputV1)
            .addInput(inputV2)
            .addInput(inputV3)
        
        txBuilder.inputsToScripts = [
            inputV1: .plutusV1Script(plutusV1Script),
            inputV2: .plutusV2Script(plutusV2Script),
            inputV3: .plutusV3Script(plutusV3Script),
            inputAdditionalV1: .plutusV1Script(additionalV1Script),
        ]
        
        let witnessSet1 = try txBuilder.buildWitnessSet(removeDupScript: true)
        #expect(witnessSet1.plutusV1Script?.count == 1)
        #expect(
            try plutusScriptHash(
                script: .plutusV1Script(witnessSet1.plutusV1Script![0]!)
            ) == additionalPlutusV1ScriptHash
        )
        #expect(witnessSet1.plutusV2Script == nil)
        #expect(witnessSet1.plutusV3Script == nil)
        
        let witnessSet2 = try txBuilder.buildWitnessSet(removeDupScript: false)
        #expect(witnessSet2.plutusV1Script?.count == 2)
        #expect(witnessSet2.plutusV2Script?.count == 1)
        #expect(witnessSet2.plutusV3Script?.count == 1)
    }
    
    @Test func testAddScriptInputPostChang() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let txIn1 = try TransactionInput(
            from: .list([
                .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(0)
            ])
        )
        
        let plutusScript = PlutusV1Script(data: Data("dummy test script".utf8))
        let scriptHash = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let scriptAddress = try Address(
            paymentPart: .scriptHash(scriptHash),
            stakingPart: .none,
            network: chainContext.networkId
        )
        let datum = try Unit().toPlutusData()
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: scriptAddress,
                amount: Value(coin: 10_000_000),
                datumHash: try datum.hash()
            )
        )
        
        let mint = try MultiAsset(
            from: [scriptHash.payload.toHex: ["TestToken": 1]]
        )
        
        let redeemer1 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        let redeemer2 = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 5_000_000, steps: 1_000_000)
        )
        
        txBuilder.mint = mint
        
        let receiver = try Address(from: .string(sender))
        
        try await txBuilder
            .addScriptInput(
                utxo1,
                script: .script(.plutusV1Script(plutusScript)),
                datum: .plutusData(datum),
                redeemer: redeemer1
            )
            .addMintingScript(
                .script(.plutusV1Script(plutusScript)),
                redeemer: redeemer2
            )
            .addOutput(
                TransactionOutput(
                    address: receiver,
                    amount: Value(coin: 5_000_000, multiAsset: mint)
                )
            )
        
        _ = try await txBuilder.build(changeAddress: receiver)
        
        let witnesses = try txBuilder.buildWitnessSet()
        
        let expectedDatum: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([datum])
        )
        let expectedPlutusV1Script: ListOrNonEmptyOrderedSet = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([
                plutusScript
            ])
        )
        let expectedRedeemers: Redeemers = .map(
            RedeemerMap([
                RedeemerKey(tag: .spend, index: 0): RedeemerValue(
                    data: try Unit().toPlutusData(),
                    exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
                ),
                RedeemerKey(tag: .mint, index: 0): RedeemerValue(
                    data: try Unit().toPlutusData(),
                    exUnits: ExecutionUnits(mem: 5_000_000, steps: 1_000_000)
                )
            ])
        )
        
        #expect(expectedDatum == witnesses.plutusData)
        #expect(expectedPlutusV1Script == witnesses.plutusV1Script)
        #expect(expectedRedeemers == witnesses.redeemers)
        
    }
    
    @Test func testTransactionWitnessSetRedeemersList() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let redeemer1 = try Redeemer(
            from: .list([
                .uint(0),
                .uint(0),
                .int(42),
                .list([.uint(1_000_000), .uint(2_000_000)]),
            ])
        )
        let redeemer2 = try Redeemer(
            from: .list([
                .uint(1),
                .uint(1),
                .string("Hello"),
                .list([.uint(3_000_000), .uint(4_000_000)]),
            ])
        )
        
        txBuilder.redeemerListOverride = [
            redeemer1,
            redeemer2
        ]
        txBuilder.useRedeemerMap = false
        
        guard case let .list(redeemers) = try txBuilder.redeemers() else {
            Issue.record("Redeemers should be list")
            return
        }
        
        #expect(redeemers.isEmpty == false)
        #expect(redeemers.count == 2)
        #expect(redeemers[0].tag == .spend)
        #expect(redeemers[0].index == 0)
        if case let .bigInt(value) = redeemers[0].data {
            #expect(value.intValue == 42)
        } else {
            Issue.record("Redeemer data type mismatch")
        }
        #expect(redeemers[0].exUnits == ExecutionUnits(mem: 1_000_000, steps: 2_000_000))
        
        #expect(redeemers[1].tag == .mint)
        #expect(redeemers[1].index == 1)
        if case let .bytes(value) = redeemers[1].data {
            #expect(value.data.toString == "Hello")
        } else {
            Issue.record("Redeemer data type mismatch")
        }
        #expect(redeemers[1].exUnits == ExecutionUnits(mem: 3_000_000, steps: 4_000_000))
    }
    
    @Test func testTransactionWitnessSetRedeemersDict() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let redeemer1 = try Redeemer(
            from: .list([
                .uint(0),
                .uint(0),
                .int(42),
                .list([.uint(1_000_000), .uint(2_000_000)]),
            ])
        )
        let redeemer2 = try Redeemer(
            from: .list([
                .uint(1),
                .uint(1),
                .string("Hello"),
                .list([.uint(3_000_000), .uint(4_000_000)]),
            ])
        )
        
        txBuilder.redeemerListOverride = [
            redeemer1,
            redeemer2
        ]
        txBuilder.useRedeemerMap = true
        
        guard case let .map(redeemers) = try txBuilder.redeemers() else {
            Issue.record("Redeemers should be map")
            return
        }
        
        let key1 = RedeemerKey(tag: .spend, index: 0)
        let key2 = RedeemerKey(tag: .mint, index: 1)
        
        #expect(redeemers.isEmpty == false)
        #expect(redeemers.count == 2)
        if case let .bigInt(value) = redeemers[key1]!.data {
            #expect(value.intValue == 42)
        } else {
            Issue.record("Redeemer data type mismatch")
        }
        #expect(
            redeemers[key1]!.exUnits == ExecutionUnits(
                mem: 1_000_000,
                steps: 2_000_000
            )
        )
        
        if case let .bytes(value) = redeemers[key2]!.data {
            #expect(value.data.toString == "Hello")
        } else {
            Issue.record("Redeemer data type mismatch")
        }
        #expect(
            redeemers[key2]!.exUnits == ExecutionUnits(
                mem: 3_000_000,
                steps: 4_000_000
            )
        )
    }
    
    @Test func testTransactionWitnessSetNoRedeemers() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let witnesses = try txBuilder.buildWitnessSet()
        #expect(witnesses.redeemers == nil)
    }
    
    @Test func testBurningAllAssetsUnderSinglePolicy() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        let senderAddress = try Address(from: .string(sender))
        
        let txIn1 = try TransactionInput(
            from: .list([
                .string("a6cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(0)
            ])
        )
        let txIn2 = try TransactionInput(
            from: .list([
                .string("b6cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(1)
            ])
        )
        let txIn3 = try TransactionInput(
            from: .list([
                .string("c6cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(2)
            ])
        )
        let txIn4 = try TransactionInput(
            from: .list([
                .string("d6cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
                .uint(3)
            ])
        )
        
        let plutusScript = PlutusV1Script(data: Data("dummy script1".utf8))
        let policyId1 = try plutusScriptHash(
            script: .plutusV1Script(plutusScript)
        )
        let multiAsset1 = try MultiAsset(from: [
            policyId1.payload.toHex: ["AssetName1": 1]
        ])
        let multiAsset2 = try MultiAsset(from: [
            policyId1.payload.toHex: ["AssetName2": 1]
        ])
        let multiAsset3 = try MultiAsset(from: [
            policyId1.payload.toHex: ["AssetName3": 1]
        ])
        let multiAsset4 = try MultiAsset(from: [
            policyId1.payload.toHex: ["AssetName4": 1]
        ])
        
        let mint = try MultiAsset(from: [
            policyId1.payload.toHex: [
                "AssetName1": -1,
                "AssetName2": -1,
                "AssetName3": -1,
                "AssetName4": -1
            ]
        ])
        
        let utxo1 = UTxO(
            input: txIn1,
            output: TransactionOutput(
                address: senderAddress,
                amount: Value(coin: 10_000_000, multiAsset: multiAsset1)
            )
        )
        let utxo2 = UTxO(
            input: txIn2,
            output: TransactionOutput(
                address: senderAddress,
                amount: Value(coin: 10_000_000, multiAsset: multiAsset2)
            )
        )
        let utxo3 = UTxO(
            input: txIn3,
            output: TransactionOutput(
                address: senderAddress,
                amount: Value(coin: 10_000_000, multiAsset: multiAsset3)
            )
        )
        let utxo4 = UTxO(
            input: txIn4,
            output: TransactionOutput(
                address: senderAddress,
                amount: Value(coin: 10_000_000, multiAsset: multiAsset4)
            )
        )
        
        txBuilder
            .addInput(utxo1)
            .addInput(utxo2)
            .addInput(utxo3)
            .addInput(utxo4)
        
        txBuilder.mint = mint

        let txBody = try await txBuilder.build(changeAddress: senderAddress)

        #expect(txBody.outputs.count == 1)
        
        for output in txBody.outputs {
            #expect(output.amount.multiAsset.isEmpty)
        }
    }
    
    @Test func testCollateralNoDuplicates() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let senderAddress = try Address(from: .string(sender))
        
        let plutusV2Script = PlutusV2Script(data: Data("dummy mint script collateral reuse test".utf8))
        let policyId = try plutusScriptHash(
            script: .plutusV2Script(plutusV2Script)
        )
        
        let redeemer = Redeemer(
            data: try Unit().toPlutusData(),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        
        let inputUTxO = UTxO(
            input: try TransactionInput(from: .list([
                .string(String(repeating: "a", count: 64)),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: senderAddress,
                amount: Value(coin: 2_800_000)
            )
        )
        let collateralUTxO = UTxO(
            input: try TransactionInput(from: .list([
                .string(String(repeating: "b", count: 64)),
                .uint(1)
            ])),
            output: TransactionOutput(
                address: senderAddress,
                amount: Value(coin: 3_000_000)
            )
        )
        
        chainContext._utxos = [inputUTxO, collateralUTxO]
        
        txBuilder
            .addInput(inputUTxO)
            .addInputAddress(.address(senderAddress))
        
        let mintAmount = 1
        txBuilder.mint = try MultiAsset(from: [
            policyId.payload.toHex: ["TestCollateralToken": mintAmount]
        ])
        
        try txBuilder.addMintingScript(
            .script(.plutusV2Script(plutusV2Script)),
            redeemer: redeemer
        )
        
        let outputValue = Value(coin: 1_000_000)
        try txBuilder.addOutput(
            TransactionOutput(
                address: senderAddress,
                amount: outputValue
            )
        )
        
        let txBody = try await txBuilder.build(changeAddress: senderAddress)
        
        #expect(txBody.inputs.contains(inputUTxO.input))
        #expect(txBody.collateral!.count > 0, "Collateral should have been selected")
        
        #expect(
            txBody.collateral!.contains(collateralUTxO.input),
            "The designated collateral UTxO was not selected"
        )
        #expect(
            txBody.collateral!.contains(inputUTxO.input),
            "The designated collateral UTxO was not selected"
        )
        
        let totalCollateralInput = collateralUTxO.output.amount + inputUTxO.output.amount
        #expect(
            totalCollateralInput == Value(
                coin: Int(txBody.totalCollateral!)
            ) + txBody.collateralReturn!.amount,
            "The total collateral input amount should match the sum of the selected UTxOs"
        )
    }
    
    @Test func testTokenTransferWithChange() async throws {
        let chainContext = MockChainContext()
        let txBuilder = TxBuilder(context: chainContext)
        
        let vaultAddress = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        let receiverAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let tokenPolicyId = ScriptHash(
            payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData
        )
        let tokenName = AssetName(from: "dux_1")
        
        chainContext._utxos = [
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("e11efc26f94a3cbf724dc052c43abf36f7a631a831acc6d783f1c9c8c52725c5"),
                    .uint(0)
                ])),
                output: TransactionOutput(
                    address: vaultAddress,
                    amount: Value(
                        coin: 1_038_710,
                        multiAsset: MultiAsset([
                            tokenPolicyId: Asset([tokenName: 1_876_083])
                        ])
                    )
                )
            )
        ]
        
        let outputValue = Value(
            coin: 1_326_255,
            multiAsset: MultiAsset([
                tokenPolicyId: Asset([tokenName: 382])
            ])
        )
        
        try txBuilder
            .addInputAddress(.address(vaultAddress))
            .addInput(UTxO(
                input: try TransactionInput(from: .list([
                    .bytes(Data(repeating: 0x31, count: 32)),
                    .uint(0)
                ])),
                output: TransactionOutput(
                    address: receiverAddress,
                    amount: Value(
                        coin: 40_000_000,
                    )
                )
            ))
            .addOutput(
                TransactionOutput(
                    address: receiverAddress,
                    amount: outputValue
                )
            )
        
        let tx = try await txBuilder.build(changeAddress: vaultAddress, mergeChange: true)
        
        #expect(tx.outputs.count == 2)
        
        let receiverOutput = tx.outputs[0]
        #expect(receiverOutput.address == receiverAddress)
        #expect(receiverOutput.amount.coin == 1_326_255)
        #expect(receiverOutput.amount.multiAsset[tokenPolicyId]![tokenName] == 382)
        
        let changeAmount = tx.outputs[1]
        #expect(changeAmount.address == vaultAddress)
        #expect(changeAmount.amount.coin  == 40_000_000 + 1_038_710 - 1_326_255 - tx.fee)
        #expect(changeAmount.amount.multiAsset[tokenPolicyId]![tokenName] == 1_876_083 - 382)
    }
}

import Foundation
import SwiftCardanoCore
import SwiftCardanoTxBuilder
import Testing

@Suite("Debug TxBuilder Tests")
struct DebugTxBuilderTests {
    
    @Test func testDebugTokenTransferAddressLookup() async throws {
        let chainContext = MockChainContext<Never>()
        let txBuilder = TxBuilder<Never, MockChainContext>(context: chainContext)
        
        let vaultAddress = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        let receiverAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let tokenPolicyId = ScriptHash(
            payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData
        )
        let tokenName = AssetName(from: "dux_1")
        
        // Set up the token UTxO at vault address
        let tokenUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("e11efc26f94a3cbf724dc052c43abf36f7a631a831acc6d783f1c9c8c52725c5"),
                .int(0)
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
        
        // Set the UTxO in mock context
        chainContext._utxos = [tokenUtxo]
        
        // Test direct address lookup
        print("Direct address lookup:")
        let directUtxos = try await chainContext.utxos(address: vaultAddress)
        print("Found \(directUtxos.count) UTxOs at vault address: \(directUtxos)")
        
        // Test lookup through AddressOrString
        print("\nAddressOrString lookup:")
        let addressOrString = AddressOrString.address(vaultAddress)
        print("AddressOrString: \(addressOrString)")
        print("asAddress: \(addressOrString.asAddress?.description ?? "nil")")
        
        if let address = addressOrString.asAddress {
            let utxosFromAddressOrString = try await chainContext.utxos(address: address)
            print("Found \(utxosFromAddressOrString.count) UTxOs via AddressOrString: \(utxosFromAddressOrString)")
        }
        
        // Test inside TxBuilder build process simulation
        print("\nTxBuilder address processing:")
        txBuilder.addInputAddress(.address(vaultAddress))
        print("Input addresses in txBuilder: \(txBuilder.inputAddresses)")
        
        for address in txBuilder.inputAddresses {
            print("Processing address: \(address)")
            if let addr = address.asAddress {
                print("Converted to Address: \(addr)")
                let utxos = try await chainContext.utxos(address: addr)
                print("Found \(utxos.count) UTxOs: \(utxos)")
            } else {
                print("Failed to convert to Address")
            }
        }
        
        // Now test the full transaction build
        print("\nFull transaction build test:")
        txBuilder
            .addInput(UTxO(
                input: try TransactionInput(from: .list([
                    .bytes(Data(repeating: 0x31, count: 32)),
                    .int(0)
                ])),
                output: TransactionOutput(
                    address: receiverAddress,
                    amount: Value(coin: 40_000_000)
                )
            ))
        
        let outputValue = Value(
            coin: 1_326_255,
            multiAsset: MultiAsset([
                tokenPolicyId: Asset([tokenName: 382])
            ])
        )
        
        try txBuilder.addOutput(
            TransactionOutput(
                address: receiverAddress,
                amount: outputValue
            )
        )
        
        do {
            let tx = try await txBuilder.build(changeAddress: vaultAddress, mergeChange: true)
            print("Transaction built successfully!")
            print("Inputs: \(tx.inputs)")
            print("Outputs: \(tx.outputs)")
        } catch {
            print("Transaction build failed: \(error)")
        }
    }
    
    @Test func testUTxOSelectorDirectly() async throws {
        let chainContext = MockChainContext<Never>()
        
        let vaultAddress = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        let receiverAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let tokenPolicyId = ScriptHash(
            payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData
        )
        let tokenName = AssetName(from: "dux_1")
        
        // Create the UTxO pool: 40M ADA + token UTxO
        let utxos = [
            // 40M ADA UTxO
            UTxO(
                input: try TransactionInput(from: .list([
                    .bytes(Data(repeating: 0x31, count: 32)),
                    .int(0)
                ])),
                output: TransactionOutput(
                    address: receiverAddress,
                    amount: Value(coin: 40_000_000)
                )
            ),
            // Token UTxO
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("e11efc26f94a3cbf724dc052c43abf36f7a631a831acc6d783f1c9c8c52725c5"),
                    .int(0)
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
        
        // Create the output that requires tokens
        let outputs = [
            TransactionOutput(
                address: receiverAddress,
                amount: Value(
                    coin: 1_326_255,
                    multiAsset: MultiAsset([
                        tokenPolicyId: Asset([tokenName: 382])
                    ])
                )
            )
        ]
        
        print("Available UTxOs:")
        for utxo in utxos {
            print("  \(utxo.input) -> \(utxo.output.amount)")
        }
        
        print("\nRequested outputs:")
        for output in outputs {
            print("  \(output.amount)")
        }
        
        // Test RandomImproveMultiAsset selector directly
        let selector = RandomImproveMultiAsset()
        
        do {
            let (selected, change) = try await selector.select(
                utxos: utxos,
                outputs: outputs,
                context: chainContext
            )
            
            print("\nSelector succeeded:")
            print("Selected UTxOs:")
            for utxo in selected {
                print("  \(utxo.input) -> \(utxo.output.amount)")
            }
            print("Change: \(change)")
        } catch {
            print("\nSelector failed: \(error)")
        }
    }
    
    @Test func testUTxOPoolConstruction() async throws {
        let chainContext = MockChainContext<Never>()
        let txBuilder = TxBuilder<Never, MockChainContext>(context: chainContext)
        
        let vaultAddress = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
        let receiverAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))
        
        let tokenPolicyId = ScriptHash(
            payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData
        )
        let tokenName = AssetName(from: "dux_1")
        
        // Set up the token UTxO at vault address
        let tokenUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .string("e11efc26f94a3cbf724dc052c43abf36f7a631a831acc6d783f1c9c8c52725c5"),
                .int(0)
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
        
        // Set the UTxO in mock context
        chainContext._utxos = [tokenUtxo]
        
        // Create the 40M ADA UTxO and add it as explicit input
        let adaUtxo = UTxO(
            input: try TransactionInput(from: .list([
                .bytes(Data(repeating: 0x31, count: 32)),
                .int(0)
            ])),
            output: TransactionOutput(
                address: receiverAddress,
                amount: Value(coin: 40_000_000)
            )
        )
        
        txBuilder
            .addInput(adaUtxo)
            .addInputAddress(.address(vaultAddress))
        
        let outputValue = Value(
            coin: 1_326_255,
            multiAsset: MultiAsset([
                tokenPolicyId: Asset([tokenName: 382])
            ])
        )
        
        try txBuilder.addOutput(
            TransactionOutput(
                address: receiverAddress,
                amount: outputValue
            )
        )
        
        print("Pre-build state:")
        print("  Selected inputs: \(txBuilder.inputs.count)")
        for input in txBuilder.inputs {
            print("    \(input.input) -> \(input.output.amount)")
        }
        print("  Input addresses: \(txBuilder.inputAddresses.count)")
        for addr in txBuilder.inputAddresses {
            print("    \(addr)")
        }
        print("  Excluded inputs: \(txBuilder.excludedInputs.count)")
        
        // Simulate the UTxO pool construction from build method
        print("\nSimulating UTxO pool construction:")
        
        var selectedUtxos: [UTxO] = []
        for input in txBuilder.inputs {
            selectedUtxos.append(input)
            print("  Added pre-selected: \(input.input)")
        }
        
        var seenUtxos = Set(selectedUtxos)
        var additionalUtxoPool: [UTxO] = []
        
        for address in txBuilder.inputAddresses {
            print("  Processing address: \(address)")
            let utxos = try await chainContext.utxos(address: address.asAddress!)
            print("    Found \(utxos.count) UTxOs at address")
            for utxo in utxos {
                print("      UTxO: \(utxo.input)")
                print("      Seen? \(seenUtxos.contains(utxo))")
                print("      Excluded? \(txBuilder.excludedInputs.contains(utxo))")
                if !seenUtxos.contains(utxo) && !txBuilder.excludedInputs.contains(utxo) {
                    additionalUtxoPool.append(utxo)
                    seenUtxos.insert(utxo)
                    print("      -> Added to pool")
                } else {
                    print("      -> Skipped")
                }
            }
        }
        
        print("\nFinal UTxO pool for selection:")
        print("  Selected inputs: \(selectedUtxos.count)")
        for utxo in selectedUtxos {
            print("    \(utxo.input) -> \(utxo.output.amount)")
        }
        print("  Additional pool: \(additionalUtxoPool.count)")
        for utxo in additionalUtxoPool {
            print("    \(utxo.input) -> \(utxo.output.amount)")
        }
    }
    
    @Test func testUnfulfilledAmountCalculation() async throws {
        let chainContext = MockChainContext<Never>()
        
        let tokenPolicyId = ScriptHash(
            payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData
        )
        let tokenName = AssetName(from: "dux_1")
        
        // Simulate the exact calculation from the failing transaction
        let requestedAmount = Value(
            coin: 1_326_255 + 165_897,  // output + estimated fee = 1,492,152
            multiAsset: MultiAsset([
                tokenPolicyId: Asset([tokenName: 382])
            ])
        )
        
        let trimmedSelectedAmount = Value(
            coin: 40_000_000,  // The 40M ADA UTxO
            multiAsset: MultiAsset([:])  // No multi-assets in the 40M UTxO
        )
        
        var unfulfilledAmount = requestedAmount - trimmedSelectedAmount
        
        print("Original calculation:")
        print("  Requested: \(requestedAmount)")
        print("  Selected: \(trimmedSelectedAmount)")
        print("  Unfulfilled: \(unfulfilledAmount)")
        
        // Test what happens when we fix the negative coin
        unfulfilledAmount.coin = max(0, unfulfilledAmount.coin)
        
        print("\nAfter fixing negative coin:")
        print("  Unfulfilled: \(unfulfilledAmount)")
        
        // Test if selector works with this unfulfilled amount
        let utxos = [
            UTxO(
                input: try TransactionInput(from: .list([
                    .string("e11efc26f94a3cbf724dc052c43abf36f7a631a831acc6d783f1c9c8c52725c5"),
                    .int(0)
                ])),
                output: TransactionOutput(
                    address: try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv")),
                    amount: Value(
                        coin: 1_038_710,
                        multiAsset: MultiAsset([
                            tokenPolicyId: Asset([tokenName: 1_876_083])
                        ])
                    )
                )
            )
        ]
        
        let outputs = [
            TransactionOutput(
                address: try Address(paymentPart: .verificationKeyHash(
                    VerificationKey(payload: Data(hex: "5797dc2cc919dfec0bb849551ebdf30d96e5cbe0f33f734a87fe826db30f7ef9")).hash()
                )),
                amount: unfulfilledAmount
            )
        ]
        
        let selector = RandomImproveMultiAsset()
        
        do {
            let (selected, change) = try await selector.select(
                utxos: utxos,
                outputs: outputs,
                context: chainContext
            )
            
            print("\nSelector with unfulfilled amount succeeded:")
            print("Selected UTxOs: \(selected.count)")
            for utxo in selected {
                print("  \(utxo.input) -> \(utxo.output.amount)")
            }
            print("Change: \(change)")
        } catch {
            print("\nSelector with unfulfilled amount failed: \(error)")
        }
    }
}

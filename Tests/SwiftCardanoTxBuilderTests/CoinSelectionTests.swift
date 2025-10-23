import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxBuilder

// Test address
nonisolated(unsafe) private let address = try! Address(
    from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x")
)

// 10 UTxOs with different ADA amount and assets
private let totalUTxOs = 10
private var utxos: [UTxO] {
    try! (0..<totalUTxOs).map { i in
        let txId = TransactionId(payload: Data(repeating: 0x31, count: 32)) // ASCII "1" = 0x31
        let input = TransactionInput(
            transactionId: txId,
            index: UInt16(i)
        )

        let amount = Value(
            coin: (i + 1) * 1_000_000,
            multiAsset: MultiAsset([
                ScriptHash(payload: Data(repeating: 1, count: 28)): Asset([
                    try AssetName(payload: Data("token\(i)".utf8)): (i + 1) * 100
                ])
            ])
        )

        let output = TransactionOutput(address: address, amount: amount)
        return UTxO(input: input, output: output)
    }
}

private func assertRequestFulfilled(request: [TransactionOutput], selected: [UTxO]) {
    let requestedAmount = request.reduce(Value()) { $0 + $1.amount }
    let selectedAmount = selected.reduce(Value()) { $0 + $1.output.amount }
    #expect(requestedAmount <= selectedAmount)
}

@Suite("LargestFirstSelector Tests")
struct LargestFirstSelectorTests {
    @Test("LargestFirst - ADA only")
    func testAdaOnly() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 15_000_000))
        ]

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext()
        )

        #expect(selected == [utxos[9], utxos[8]])
        assertRequestFulfilled(request: request, selected: selected)
    }

    @Test("LargestFirst - Multiple request outputs")
    func testMultipleOutputs() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 9_000_000)),
            TransactionOutput(address: address, amount: Value(coin: 6_000_000)),
        ]

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext()
        )

        #expect(selected == [utxos[9], utxos[8]])
        assertRequestFulfilled(request: request, selected: selected)
    }

    @Test("LargestFirst - Fee effect")
    func testFeeEffect() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 10_000_000))
        ]

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext(),
            respectMinUtxo: false
        )

        #expect(selected == [utxos[9], utxos[8]])
        assertRequestFulfilled(request: request, selected: selected)
    }

    @Test("LargestFirst - No fee effect")
    func testNoFeeEffect() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 10_000_000))
        ]

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext(),
            includeMaxFee: false,
            respectMinUtxo: false
        )

        #expect(selected == [utxos[9]])
    }

    @Test("LargestFirst - No fee but respect min UTxO")
    func testNoFeeRespectMinUtxo() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 10_000_000))
        ]

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext(),
            includeMaxFee: false,
            respectMinUtxo: true
        )

        #expect(selected == [utxos[9], utxos[8]])
    }

    @Test("LargestFirst - Insufficient balance")
    func testInsufficientBalance() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 1_000_000_000))
        ]

        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await selector.select(
                utxos: utxos,
                outputs: request,
                context: MockChainContext()
            )
        }
    }

    @Test("LargestFirst - Max input count")
    func testMaxInputCount() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 15_000_000))
        ]

        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await selector.select(
                utxos: utxos,
                outputs: request,
                context: MockChainContext(),
                maxInputCount: 1
            )
        }
    }

    @Test("LargestFirst - Multi asset")
    func testMultiAsset() async throws {
        let selector = LargestFirstSelector()
        let request = [
            TransactionOutput(
                address: address,
                amount: Value(
                    coin: 1_500_000,
                    multiAsset: MultiAsset([
                        ScriptHash(payload: Data(repeating: 1, count: 28)): Asset([
                            try AssetName(payload: Data("token0".utf8)): 50
                        ])
                    ])
                )
            )
        ]

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext()
        )
        let expected = Array(utxos.reversed())

        #expect(selected == expected)
        assertRequestFulfilled(request: request, selected: selected)
    }
}

@Suite("RandomImproveMultiAsset Tests")
struct RandomImproveMultiAssetTests {
    
    @Test("RandomImprove - ADA only")
    func testAdaOnly() async throws {
        let request1 = [
            TransactionOutput(address: address, amount: Value(coin: 15_000_000))
        ]

        var sequence1: [Int] = Array(0..<totalUTxOs).reversed()
        let selector1 = RandomImproveMultiAsset(randomGenerator: {
            return sequence1.removeFirst()
        })

        let (selected1, _) = try await selector1.select(
            utxos: utxos,
            outputs: request1,
            context: MockChainContext()
        )

        let expected = Array(utxos.reversed().prefix(4))

        #expect(selected1 == expected)
        assertRequestFulfilled(request: request1, selected: selected1)

        let request2 = [
            TransactionOutput(address: address, amount: Value(coin: 9_000_000)),
            TransactionOutput(address: address, amount: Value(coin: 6_000_000)),
        ]

        var sequence2: [Int] = Array(0..<totalUTxOs).reversed()
        let selector2 = RandomImproveMultiAsset(randomGenerator: {
            return sequence2.removeFirst()
        })

        let (selected2, _) = try await selector2.select(
            utxos: utxos,
            outputs: request2,
            context: MockChainContext()
        )

        #expect(selected2 == expected)
        assertRequestFulfilled(request: request2, selected: selected2)
    }

    @Test("RandomImprove - Fee effect")
    func testFeeEffect() async throws {
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 9_000_000))
        ]

        var sequence: [Int] = Array(0..<totalUTxOs).reversed()
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext()
        )

        #expect(selected == [utxos[9], utxos[8], utxos[5]])
        assertRequestFulfilled(request: request, selected: selected)
    }

    @Test("RandomImprove - No fee effect")
    func testNoFeeEffect() async throws {
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 9_000_000))
        ]

        var sequence: [Int] = Array(0..<totalUTxOs).reversed()
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext(),
            includeMaxFee: false
        )

        #expect(selected == [utxos[9], utxos[8]])
        assertRequestFulfilled(request: request, selected: selected)
    }

    @Test("RandomImprove - No fee but respect min UTxO")
    func testNoFeeRespectMinUtxo() async throws {
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 500_000))
        ]

        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext(),
            includeMaxFee: false,
            respectMinUtxo: true
        )

        #expect(selected == [utxos[0], utxos[1]])
        assertRequestFulfilled(request: request, selected: selected)
    }

    @Test("RandomImprove - UTxO depleted")
    func testUtxoDepleted() async throws {
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 1_000_000_000))
        ]

        var sequence: [Int] = Array(0..<totalUTxOs).reversed()
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await selector.select(
                utxos: utxos,
                outputs: request,
                context: MockChainContext()
            )
        }
    }

    @Test("RandomImprove - Max input count")
    func testMaxInputCount() async throws {
        let request = [
            TransactionOutput(address: address, amount: Value(coin: 15_000_000))
        ]

        var sequence: [Int] = Array(0..<totalUTxOs).reversed()
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await selector.select(
                utxos: utxos,
                outputs: request,
                context: MockChainContext(),
                maxInputCount: 1
            )
        }
    }

    @Test("RandomImprove - Multi asset")
    func testMultiAsset() async throws {
        let request = [
            TransactionOutput(
                address: address,
                amount: Value(
                    coin: 1_500_000,
                    multiAsset: MultiAsset([
                        ScriptHash(payload: Data(repeating: 1, count: 28)): Asset([
                            try AssetName(payload: Data("token0".utf8)): 50,
                            try AssetName(payload: Data("token3".utf8)): 50,
                        ])
                    ])
                )
            )
        ]

        var sequence: [Int] = [9, 8, 3, 6, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: {
            return sequence.removeFirst()
        })

        let (selected, _) = try await selector.select(
            utxos: utxos,
            outputs: request,
            context: MockChainContext()
        )

        #expect(selected == [utxos[9], utxos[8], utxos[3], utxos[7], utxos[0]])
        assertRequestFulfilled(request: request, selected: selected)
    }
}

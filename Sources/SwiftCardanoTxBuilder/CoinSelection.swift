/**
 This module contains algorithms that select UTxOs from a parent list to satisfy some output constraints.
 */

import Foundation
import SwiftCardanoChain
import SwiftCardanoCore


// MARK: - Constants

// Fake address used for minimum UTxO calculations
struct FakeAddress {
    static var address: Address {
        try! Address(
            from: .string("addr1q8m9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwta8k2v59pcduem5uw253zwke30x9mwes62kfvqnzg38kuh6q966kg7")
        )
    }
}

// MARK: - UTxOSelector Protocol

/// UTxOSelector defines an interface through which a subset of UTxOs should be selected from a parent set
/// with a selection strategy and given constraints.
public protocol UTxOSelector {
    /**
     From an input list of UTxOs, select a subset of UTxOs whose sum (including ADA and multi-assets)
     is equal to or larger than the sum of a set of outputs.

     - Parameters:
        - utxos: A list of UTxO to select from.
        - outputs: A list of transaction outputs which the selected set should satisfy.
        - context: A chain context where protocol parameters could be retrieved.
        - maxInputCount: Max number of input UTxOs to select.
        - includeMaxFee: Have selected UTxOs to cover transaction fee. Defaults to true. If disabled,
          there is a possibility that selected UTxO are not able to cover the fee of the transaction.
        - respectMinUtxo: Respect minimum amount of ADA required to hold a multi-asset bundle in the change.
          Defaults to true. If disabled, the selection will not add addition amount of ADA to change even
          when the amount is too small to hold a multi-asset bundle.

     - Returns: A tuple containing:
        - selected: A list of selected UTxOs.
        - changes: Change amount to be returned.

     - Throws:
        - CardanoTxBuilderError.insufficientUTxOBalance: When total value of input UTxO is less than requested outputs.
        - CardanoTxBuilderError.maxInputCountExceeded: When number of selected UTxOs exceeds `maxInputCount`.
        - CardanoTxBuilderError.inputUTxODepleted: When the algorithm has depleted input UTxOs but selection should continue.
        - CardanoTxBuilderError.utxoSelectionFailed: When selection fails for reasons besides the three above.
     */
    func select(
        utxos: [UTxO],
        outputs: [TransactionOutput],
        context: any ChainContext,
        maxInputCount: Int?,
        includeMaxFee: Bool,
        respectMinUtxo: Bool
    ) async throws -> ([UTxO], Value)
}


// MARK: - LargestFirstSelector

/// Largest first selection algorithm as specified in
/// https://github.com/cardano-foundation/CIPs/tree/master/CIP-0002#largest-first.
///
/// This implementation adds transaction fee into consideration.
public class LargestFirstSelector: UTxOSelector {

    public init() {}

    public func select(
        utxos: [UTxO],
        outputs: [TransactionOutput],
        context: any ChainContext,
        maxInputCount: Int? = nil,
        includeMaxFee: Bool = true,
        respectMinUtxo: Bool = true
    ) async throws -> ([UTxO], Value) {
        var available = utxos.sorted {
            $0.output.lovelace > $1.output.lovelace
        }
        let maxFee = includeMaxFee ? try await maxTxFee(context) : 0
        var totalRequested = Value(coin: Int(maxFee))

        for output in outputs {
            totalRequested = totalRequested + output.amount
        }

        var selected: [UTxO] = []
        var selectedAmount = Value()

        while !(totalRequested <= selectedAmount) {
            if available.isEmpty {
                throw CardanoTxBuilderError.insufficientUTxOBalance("UTxO Balance insufficient!")
            }

            let toAdd = available.removeFirst()
            selected.append(toAdd)
            selectedAmount = selectedAmount + toAdd.output.amount

            if let maxInputCount = maxInputCount, selected.count > maxInputCount {
                throw CardanoTxBuilderError.maxInputCountExceeded(
                    "Max input count: \(maxInputCount) exceeded!")
            }
        }

        if respectMinUtxo {
            let change = selectedAmount - totalRequested
            let minChangeAmount = try await minLovelacePostAlonzo(
                TransactionOutput(address: FakeAddress.address, amount: change),
                context
            )

            if change.coin < minChangeAmount {
                let additional = try await self.select(
                    utxos: available,
                    outputs: [
                        TransactionOutput(
                            address: FakeAddress.address,
                            amount: Value(
                                coin: Int(minChangeAmount) - change.coin
                            )
                        )
                    ],
                    context: context,
                    maxInputCount: maxInputCount.map { $0 - selected.count },
                    includeMaxFee: false,
                    respectMinUtxo: false
                ).0

                for utxo in additional {
                    selected.append(utxo)
                    selectedAmount = selectedAmount + utxo.output.amount
                }
            }
        }

        return (selected, selectedAmount - totalRequested)
    }
}

// MARK: - RandomImproveMultiAsset

/// Random-improve selection algorithm as specified in
/// https://github.com/cardano-foundation/CIPs/tree/master/CIP-0002#random-improve.
///
/// Because the original algorithm does not take multi-assets into consideration, this implementation is slightly
/// different from the algorithm. The main modification is that it merges all requested transaction outputs into one,
/// including all native assets, and then treat each merged native asset as an individual transaction output request.
///
/// This idea is inspired by Nami wallet: https://github.com/Berry-Pool/nami-wallet/blob/main/src/lib/coinSelection.js
///
/// Note:
/// Although this implementation is similar to the original Random-improve algorithm, and it is being used by some
/// wallets, there are no substantial evidences or proofs showing that this implementation will still be able to
/// correctly optimize UTxO selection based on
/// [three heuristics](https://github.com/cardano-foundation/CIPs/tree/master/CIP-0002#motivating-principles)
/// mentioned in the doc.
public class RandomImproveMultiAsset: UTxOSelector {
    private let randomGenerator: (() -> Int)?

    /**
     Initialize with an optional random generator function.

     - Parameter randomGenerator: A function that generates random integers. If nil, the system random generator will be used.
     */
    public init(randomGenerator: (() -> Int)? = nil) {
        self.randomGenerator = randomGenerator
    }

    private func getNextRandom(utxos: [UTxO]) throws -> (Int, UTxO) {
        if utxos.isEmpty {
            throw CardanoTxBuilderError.inputUTxODepleted("Input UTxOs depleted!")
        }

        let index: Int
        if let generator = randomGenerator {
            index = generator()
            if index >= utxos.count {
                throw CardanoTxBuilderError.utxoSelectionFailed("Random index: \(index) out of range!")
            }
        } else {
            index = Int.random(in: 0..<utxos.count)
        }

        return (index, utxos[index])
    }

    private func randomSelectSubset(
        amount: Value,
        remaining: inout [UTxO],
        selected: inout [UTxO],
        selectedAmount: inout Value
    ) throws {
        while !(amount <= selectedAmount) {
            if remaining.isEmpty {
                throw CardanoTxBuilderError.inputUTxODepleted("Input UTxOs depleted!")
            }

            let (index, toAdd) = try getNextRandom(utxos: remaining)
            selected.append(toAdd)
            selectedAmount = selectedAmount + toAdd.output.amount
            remaining.remove(at: index)
        }
    }

    private func splitByAsset(value: Value) -> [Value] {
        // Extract ADA
        var assets: [Value] = value.coin > 0 ? [Value(coin: value.coin)] : []

        // Extract native assets
        for (policyId, assetMap) in value.multiAsset.data {
            for (assetName, amount) in assetMap.data {
                if amount > 0 {
                    var multiAsset = MultiAsset([:])
                    multiAsset[policyId] = Asset([assetName:amount])
                    assets.append(Value(coin: 0, multiAsset: multiAsset))
                }
            }
        }

        return assets
    }

    private func getSingleAssetVal(value: Value) -> UInt64 {
        if value.coin > 0 {
            return UInt64(value.coin)
        } else {
            // Get the first (and only) asset value
            let policyId = value.multiAsset.data.keys.first!
            let assetName = value.multiAsset[policyId]!.data.keys.first!
            return UInt64(value.multiAsset[policyId]![assetName]!)
        }
    }
    
    /// The first argument contains only one asset. Find the absolute difference between this asset and
    /// the corresponding value of the same asset in the second argument
    /// - Parameters:
    ///   - a: The first value containing only one asset
    ///   - b: The second value containing the same asset
    /// - Returns: Difference between the two values
    private func findDiffByFormer(a: Value, b: Value) -> Int64 {
        if a.coin > 0 {
            return Int64(a.coin) - Int64(b.coin)
        } else {
            let policyId = a.multiAsset.data.keys.first!
            let assetName = a.multiAsset[policyId]!.data.keys.first!
            
            let aAssetAmount = a.multiAsset[policyId]?[assetName] ?? 0
            let bAssetAmount = b.multiAsset[policyId]?[assetName] ?? 0
            return Int64(aAssetAmount) - Int64(bAssetAmount)
        }
    }

    private func improve(
        selected: inout [UTxO],
        selectedAmount: inout Value,
        remaining: [UTxO],
        ideal: Value,
        upperBound: Value,
        maxInputCount: Int?
    ) throws {
        if remaining.isEmpty || findDiffByFormer(a: ideal, b: selectedAmount) <= 0 {
            // In case where there is no remaining UTxOs or we already selected more than ideal,
            // we cannot improve by randomly adding more UTxOs, therefore return immediate.
            return
        }

        if let maxInputCount = maxInputCount, selected.count > maxInputCount {
            throw CardanoTxBuilderError.maxInputCountExceeded(
                "Max input count: \(maxInputCount) exceeded!")
        }

        let (index, toAdd) = try getNextRandom(utxos: remaining)
        let potentialAmount = selectedAmount + toAdd.output.amount

        if abs(findDiffByFormer(a: ideal, b: potentialAmount))
            < abs(findDiffByFormer(a: ideal, b: selectedAmount))
            && findDiffByFormer(a: upperBound, b: potentialAmount) >= 0
        {
            selected.append(toAdd)
            selectedAmount = potentialAmount
        }

        var newRemaining = remaining
        newRemaining.remove(at: index)
        try improve(
            selected: &selected,
            selectedAmount: &selectedAmount,
            remaining: newRemaining,
            ideal: ideal,
            upperBound: upperBound,
            maxInputCount: maxInputCount
        )
    }

    public func select(
        utxos: [UTxO],
        outputs: [TransactionOutput],
        context: any ChainContext,
        maxInputCount: Int? = nil,
        includeMaxFee: Bool = true,
        respectMinUtxo: Bool = true
    ) async throws -> ([UTxO], Value) {
        // Shallow copy the list
        var remaining = utxos
        let maxFee = includeMaxFee ? try await maxTxFee(context) : 0
        var requestSum = Value(coin: Int(maxFee))

        for output in outputs {
            requestSum = requestSum + output.amount
        }

        let assets = splitByAsset(value: requestSum)
        let requestSorted = assets.sorted {
            getSingleAssetVal(value: $0) > getSingleAssetVal(value: $1)
        }

        // Phase 1 - random select
        var selected: [UTxO] = []
        var selectedAmount = Value()

        for request in requestSorted {
            try randomSelectSubset(
                amount: request,
                remaining: &remaining,
                selected: &selected,
                selectedAmount: &selectedAmount
            )

            if let maxInputCount = maxInputCount, selected.count > maxInputCount {
                throw CardanoTxBuilderError.maxInputCountExceeded(
                    "Max input count: \(maxInputCount) exceeded!"
                )
            }
        }

        // Phase 2 - improve current selection
        for request in requestSorted.reversed() {
            let ideal = request + request
            let upperBound = ideal + request
            let numSelectedBefore = selected.count

            do {
                let remainingCopy = remaining
                try improve(
                    selected: &selected,
                    selectedAmount: &selectedAmount,
                    remaining: remainingCopy,
                    ideal: ideal,
                    upperBound: upperBound,
                    maxInputCount: maxInputCount
                )
            } catch {
                // Ignore errors during improvement phase
            }

            let newSelected = Array(selected[numSelectedBefore...])
            remaining = remaining.filter { !newSelected.contains($0) }
        }

        if respectMinUtxo {
            let change = selectedAmount - requestSum
            let minChangeAmount = try await minLovelacePostAlonzo(
                TransactionOutput(address: FakeAddress.address, amount: change),
                context
            )

            if change.coin < minChangeAmount {
                let additional = try await select(
                    utxos: remaining,
                    outputs: [
                        TransactionOutput(
                            address: FakeAddress.address,
                            amount: Value(
                                coin: Int(minChangeAmount) - change.coin
                            )
                        )
                    ],
                    context: context,
                    maxInputCount: maxInputCount.map { $0 - selected.count },
                    includeMaxFee: false,
                    respectMinUtxo: false
                ).0

                for utxo in additional {
                    selected.append(utxo)
                    selectedAmount = selectedAmount + utxo.output.amount
                }
            }
        }

        return (selected, selectedAmount - requestSum)
    }
}

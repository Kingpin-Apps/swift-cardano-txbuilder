import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftNaCl
import CBORCodable

// MARK: - Utility Functions

public struct Utils {
    
    /// Calculate plutus script data hash
    ///
    /// - Parameters:
    ///   - redeemers: Redeemers to include.
    ///   - datums: Datums to include.
    ///   - costModels: Cost models.
    /// - Returns: Plutus script data hash
    public static func scriptDataHash(
        redeemers: Redeemers? = .map(RedeemerMap()),
        datums: ListOrNonEmptyOrderedSet<Datum>? = nil,
        costModels: CostModels? = nil
    ) throws -> ScriptDataHash {
        
        let redeemersIsEmpty: Bool
        switch redeemers {
            case .list(let list):
                redeemersIsEmpty = list.isEmpty
            case .map(let map):
                redeemersIsEmpty = map.count == 0
            case .none:
                redeemersIsEmpty = true
        }
        
        let costModelsBytes: Data
        if redeemersIsEmpty {
            costModelsBytes = try CBOREncoder().encode(CBOR.map([:]))
        } else if let costModels = costModels {
            costModelsBytes = try costModels.toCBORData()
        } else {
            let costModels = try CostModels.forScriptDataHash()
            costModelsBytes = try costModels.toCBORData()
        }
        
        let datumBytes = try datums?.toCBORData() ?? Data()
        let redeemerBytes = try redeemers?.toCBORData() ?? Data()
        
        return ScriptDataHash(
            payload: try SwiftNaCl.Hash().blake2b(
                data: redeemerBytes + datumBytes + costModelsBytes,
                digestSize: SCRIPT_DATA_HASH_SIZE,
                encoder: RawEncoder.self
            )
        )
    }
    
    /// Calculate fee for reference scripts.
    ///
    /// - Parameters:
    ///   - context: A chain context.
    ///   - scriptsSize: Size of reference scripts in bytes.
    /// - Returns: Fee for reference scripts.
    /// - Throws: ValueError if scripts size exceeds maximum allowed size
    public static func tieredReferenceScriptFee(_ context: any ChainContext, scriptsSize: UInt64) async throws -> UInt64 {
        try await referenceScriptFeeTiers(context, scriptsSize: scriptsSize).fee
    }

    /// The reference-script fee, tier by tier.
    ///
    /// Reference-script bytes are charged in tiers of `range` bytes, each tier
    /// at `multiplier` times the price of the one before.
    public static func referenceScriptFeeTiers(
        _ context: any ChainContext, scriptsSize: UInt64
    ) async throws -> (tiers: [FeeBreakdown.ReferenceScriptTier], fee: UInt64) {
        let protocolParameters = try await context.protocolParameters()

        guard let maxSize = protocolParameters.maxReferenceScriptsSize,
            let pricing = protocolParameters.minFeeReferenceScripts,
            let base = pricing.base, let range = pricing.range, let multiplier = pricing.multiplier
        else {
            return ([], 0)
        }
        if scriptsSize > maxSize {
            throw CardanoTxBuilderError.valueError(
                "Reference scripts size: \(scriptsSize) exceeds maximum allowed size (\(maxSize))."
            )
        }

        var tiers: [FeeBreakdown.ReferenceScriptTier] = []
        var total: Double = 0.0
        if scriptsSize > 0 {
            var price = base
            let r = ceil(range)
            var remainingSize = scriptsSize
            while remainingSize > UInt64(r) {
                tiers.append(.init(bytes: UInt64(r), pricePerByte: price, fee: price * r))
                total += price * r
                remainingSize = remainingSize - UInt64(r)
                price = price * multiplier
            }
            tiers.append(.init(bytes: remainingSize, pricePerByte: price, fee: price * Double(remainingSize)))
            total += price * Double(remainingSize)
        }
        return (tiers, UInt64(ceil(total)))
    }

    /// Calculate the transaction fee based on the length of a transaction's CBOR bytes and script execution.
    ///
    /// - Parameters:
    ///   - context: The chain context containing protocol parameters.
    ///   - length: The length of CBOR bytes, which could usually be derived by `tx.toCbor().count`.
    ///   - execSteps: Number of execution steps run by plutus scripts in the transaction.
    ///   - maxMemUnit: Max number of memory units run by plutus scripts in the transaction.
    ///   - refScriptSize: Size of referenced scripts in the transaction.
    /// - Returns: Minimum acceptable transaction fee.
    public static func calculateFee(
        _ context: any ChainContext,
        length: UInt64,
        execSteps: UInt64 = 0,
        maxMemUnit: UInt64 = 0,
        refScriptSize: UInt64 = 0
    ) async throws -> UInt64 {
        try await feeBreakdown(
            context, length: length, execSteps: execSteps, maxMemUnit: maxMemUnit, refScriptSize: refScriptSize
        ).total
    }

    /// The fee ``calculateFee(_:length:execSteps:maxMemUnit:refScriptSize:)``
    /// computes, item by item.
    public static func feeBreakdown(
        _ context: any ChainContext,
        length: UInt64,
        execSteps: UInt64 = 0,
        maxMemUnit: UInt64 = 0,
        refScriptSize: UInt64 = 0
    ) async throws -> FeeBreakdown {
        let protocolParameters = try await context.protocolParameters()

        let sizeFee = UInt64(ceil(Double(length) * Double(protocolParameters.txFeePerByte)))
        let fixedFee = UInt64(ceil(Double(protocolParameters.txFeeFixed)))
        let stepsFee = UInt64(ceil(Double(execSteps) * Double(protocolParameters.executionUnitPrices.priceSteps)))
        let memoryFee = UInt64(ceil(Double(maxMemUnit) * Double(protocolParameters.executionUnitPrices.priceMemory)))
        let (tiers, referenceScriptFee) = try await referenceScriptFeeTiers(context, scriptsSize: refScriptSize)

        return FeeBreakdown(
            sizeBytes: length, feePerByte: UInt64(protocolParameters.txFeePerByte), sizeFee: sizeFee,
            fixedFee: fixedFee, steps: execSteps, stepsFee: stepsFee, memory: maxMemUnit, memoryFee: memoryFee,
            referenceScriptBytes: refScriptSize, referenceScriptTiers: tiers, referenceScriptFee: referenceScriptFee
        )
    }
    
    /// Calculate the maximum transaction fee based on protocol parameters.
    ///
    /// - Parameters:
    ///   - context: The chain context containing protocol parameters.
    ///   - refScriptSize: Size of reference scripts in the transaction.
    /// - Returns: The maximum transaction fee in lovelace.
    public static func maxTxFee(_ context: any ChainContext, refScriptSize: UInt64 = 0) async throws -> UInt64 {
        let protocolParameters = try await context.protocolParameters()
        
        return try await Utils.calculateFee(
            context,
            length: UInt64(protocolParameters.maxTxSize),
            execSteps: UInt64(protocolParameters.maxTxExecutionUnits.steps),
            maxMemUnit: UInt64(protocolParameters.maxTxExecutionUnits.memory),
            refScriptSize: refScriptSize
        )
    }
    
    /// Calculate size of a multi-asset in words. (1 word = 8 bytes)
    ///
    /// - Parameter multiAsset: Input multi asset.
    /// - Returns: Number of words.
    public static func bundleSize(_ multiAsset: MultiAsset) -> UInt64 {
        let numPolicies = multiAsset.data.count
        var numAssets = 0
        var totalAssetNameLen = 0
        
        // Only unique asset names are counted
        // See GitHub issue: https://github.com/Emurgo/cardano-serialization-lib/issues/194
        var uniqueAssets = Set<Data>()
        for policy in multiAsset.data.keys {
            if let assets = multiAsset[policy] {
                numAssets += assets.count
                for assetName in assets.data.keys {
                    if !uniqueAssets.contains(assetName.payload) {
                        uniqueAssets.insert(assetName.payload)
                        totalAssetNameLen += assetName.payload.count
                    }
                }
            }
        }
        
        let a = numAssets * 12
        let b = numPolicies * Int(SCRIPT_HASH_SIZE)
        
        let byteLen = a + totalAssetNameLen + b
        return 6 + UInt64((byteLen + 7) / 8)
    }
    
    /// Calculate minimum lovelace a transaction output needs to hold.
    ///
    /// - Parameters:
    ///   - context: The chain context containing protocol parameters.
    ///   - output: A transaction output (for post-alonzo transactions).
    ///   - amount: Amount from a transaction output (for pre-alonzo transactions).
    ///   - hasDatum: Whether the transaction output contains datum hash (for pre-alonzo transactions).
    /// - Returns: Minimum required lovelace amount for this transaction output.
    public static func minLovelace(
        _ context: any ChainContext,
        output: TransactionOutput? = nil,
        amount: Value? = nil,
        hasDatum: Bool = false
    ) async throws -> UInt64 {
        if let output = output {
            return try await Utils.minLovelacePostAlonzo(output, context)
        } else {
            return try await Utils.minLovelacePreAlonzo(amount, context, hasDatum: hasDatum)
        }
    }
    
    /// Calculate minimum lovelace a transaction output needs to hold pre-alonzo.
    ///
    /// - Parameters:
    ///   - amount: Amount from a transaction output.
    ///   - context: The chain context containing protocol parameters.
    ///   - hasDatum: Whether the transaction output contains datum hash.
    /// - Returns: Minimum required lovelace amount for this transaction output.
    public static func minLovelacePreAlonzo(
        _ amount: Value?,
        _ context: any ChainContext,
        hasDatum: Bool = false
    ) async throws -> UInt64 {
        let protocolParameters = try await context.protocolParameters()
        
        if amount == nil || amount?.multiAsset.data.isEmpty ?? true {
            return UInt64(protocolParameters.utxoCostPerByte)
        }
        
        let bSize = Utils.bundleSize(amount!.multiAsset)
        let utxoEntrySize: UInt64 = 27
        let dataHashSize: UInt64 = hasDatum ? 10 : 0
        let finalizedSize = utxoEntrySize + bSize + dataHashSize
        
        return finalizedSize * UInt64(protocolParameters.coinsPerUtxoWord)
    }
    
    /// Calculate minimum lovelace a transaction output needs to hold post alonzo.
    ///
    /// - Parameters:
    ///   - output: The transaction output to calculate minimum lovelace for.
    ///   - context: The chain context containing protocol parameters.
    /// - Returns: The minimum lovelace required.
    public static func minLovelacePostAlonzo(_ output: TransactionOutput, _ context: any ChainContext) async throws -> UInt64
    {
        let protocolParameters = try await context.protocolParameters()
        let constantOverhead: UInt64 = 160
        
        var amount = output.amount
        
        // If the amount of ADA is 0, a default value of 1 ADA will be used
        if amount.coin == 0 {
            amount = Value(coin: 1_000_000, multiAsset: amount.multiAsset)
        }
        
        // Make sure we are using post-alonzo output
        let tmpOut = TransactionOutput(
            address: output.address,
            amount: amount,
            datumHash: output.datumHash,
            datumOption: output.datumOption,
            script: output.script,
            postAlonzo: true
        )
        
        return (constantOverhead + UInt64(try tmpOut.toCBORData().count))
        * UInt64(protocolParameters.utxoCostPerByte)
    }
}

/// A transaction fee, item by item.
public struct FeeBreakdown: Sendable, Equatable {
    /// One tier of the reference-script fee.
    public struct ReferenceScriptTier: Sendable, Equatable {
        public let bytes: UInt64
        public let pricePerByte: Double
        public let fee: Double
    }

    /// The transaction's size in bytes.
    public let sizeBytes: UInt64
    public let feePerByte: UInt64
    /// `sizeBytes × feePerByte`.
    public let sizeFee: UInt64
    /// The fixed part of every fee.
    public let fixedFee: UInt64
    /// Plutus execution steps, and what they cost.
    public let steps: UInt64
    public let stepsFee: UInt64
    /// Plutus execution memory, and what it costs.
    public let memory: UInt64
    public let memoryFee: UInt64
    /// Bytes of reference scripts the transaction uses, and their tiered cost.
    public let referenceScriptBytes: UInt64
    public let referenceScriptTiers: [ReferenceScriptTier]
    public let referenceScriptFee: UInt64
    /// A fixed amount added on top, such as ``TxBuilder/feeBuffer``.
    public var buffer: UInt64 = 0

    /// The script-execution part: steps plus memory.
    public var executionFee: UInt64 { stepsFee + memoryFee }

    /// The whole fee.
    public var total: UInt64 { sizeFee + fixedFee + executionFee + referenceScriptFee + buffer }
}

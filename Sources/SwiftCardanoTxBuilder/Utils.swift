import BigInt
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

    /// Conway's reference-script tiers, fixed by the ledger rather than
    /// set by protocol parameters: a stride of 25 KiB, each tier 6/5 the
    /// price of the last.
    static let conwayReferenceScriptTierBytes: UInt32 = 25_600
    static let conwayReferenceScriptTierMultiplier = NonNegativeInterval(numerator: 6, denominator: 5)
    static let conwayMaxReferenceScriptsSize: Int64 = 204_800
    /// The most reference-script tiers a fee may span. Conway's ledger
    /// constants give at most 8.
    static let maxReferenceScriptTiers: UInt64 = 64

    /// The reference-script fee, tier by tier.
    ///
    /// Reference-script bytes are charged in tiers of `range` bytes, each tier
    /// at `multiplier` times the price of the one before. The fee is the
    /// ledger's `tierRefScriptFee`: the exact rational sum over every tier,
    /// rounded down once. Each tier's `pricePerByte` and `fee` are that
    /// tier's exact amounts as a `Double`, for display.
    public static func referenceScriptFeeTiers(
        _ context: any ChainContext, scriptsSize: UInt64
    ) async throws -> (tiers: [FeeBreakdown.ReferenceScriptTier], fee: UInt64) {
        let protocolParameters = try await context.protocolParameters()

        // Parameters that state only the price per byte, as many providers'
        // do, take Conway's fixed tiers: 25 KiB, each 1.2 times the last, up
        // to 200 KiB a transaction. Charging nothing would leave the fee too
        // small for the node.
        let base: NonNegativeInterval, range: UInt32, multiplier: NonNegativeInterval
        if let pricing = protocolParameters.minFeeReferenceScripts,
            let tierBase = pricing.base, let tierRange = pricing.range, let tierMultiplier = pricing.multiplier
        {
            (base, range, multiplier) = (tierBase, tierRange, tierMultiplier)
        } else if let perByte = protocolParameters.minFeeRefScriptCostPerByte {
            (base, range, multiplier) = (perByte, Self.conwayReferenceScriptTierBytes, Self.conwayReferenceScriptTierMultiplier)
        } else {
            return ([], 0)
        }
        guard range > 0, multiplier.numerator > 0, multiplier.denominator > 0, base.denominator > 0 else {
            throw CardanoTxBuilderError.valueError(
                "Reference-script pricing needs a positive stride and multiplier: range \(range), multiplier \(multiplier.numerator)/\(multiplier.denominator).")
        }
        let maxSize = protocolParameters.maxReferenceScriptsSize ?? Self.conwayMaxReferenceScriptsSize
        if scriptsSize > maxSize {
            throw CardanoTxBuilderError.valueError(
                "Reference scripts size: \(scriptsSize) exceeds maximum allowed size (\(maxSize))."
            )
        }

        // Conway has at most 8 tiers. A provider stride far below the ledger's
        // would make this exact-rational loop run once per byte, so refuse it.
        let tierCount = scriptsSize == 0 ? 0 : (scriptsSize - 1) / UInt64(range) + 1
        guard tierCount <= Self.maxReferenceScriptTiers else {
            throw CardanoTxBuilderError.valueError(
                "Reference-script pricing stride \(range) gives \(tierCount) tiers for \(scriptsSize) bytes; at most \(Self.maxReferenceScriptTiers) are allowed.")
        }

        var tiers: [FeeBreakdown.ReferenceScriptTier] = []
        var total = Rational(0)
        if scriptsSize > 0 {
            var price = Rational(base)
            let step = Rational(multiplier)
            let stride = UInt64(range)
            var remainingSize = scriptsSize
            while remainingSize > stride {
                let fee = price * Rational(BigInt(stride))
                tiers.append(.init(bytes: stride, pricePerByte: price.double, fee: fee.double))
                total = total + fee
                remainingSize -= stride
                price = price * step
            }
            let fee = price * Rational(BigInt(remainingSize))
            tiers.append(.init(bytes: remainingSize, pricePerByte: price.double, fee: fee.double))
            total = total + fee
        }
        return (tiers, try total.floor.coin("Reference-script fee"))
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
        ).checkedTotal()
    }

    /// The fee ``calculateFee(_:length:execSteps:maxMemUnit:refScriptSize:)``
    /// computes, item by item, as the ledger's `getConwayMinFeeTx` does.
    public static func feeBreakdown(
        _ context: any ChainContext,
        length: UInt64,
        execSteps: UInt64 = 0,
        maxMemUnit: UInt64 = 0,
        refScriptSize: UInt64 = 0
    ) async throws -> FeeBreakdown {
        let protocolParameters = try await context.protocolParameters()
        let prices = protocolParameters.executionUnitPrices

        let (sizeFee, sizeOverflow) = length.multipliedReportingOverflow(by: protocolParameters.txFeePerByte)
        guard !sizeOverflow else {
            throw CardanoTxBuilderError.valueError("Size fee of \(length) bytes overflows")
        }
        let stepsCost = Rational(prices.priceSteps) * Rational(BigInt(execSteps))
        let memoryCost = Rational(prices.priceMemory) * Rational(BigInt(maxMemUnit))
        let (tiers, referenceScriptFee) = try await referenceScriptFeeTiers(context, scriptsSize: refScriptSize)

        return FeeBreakdown(
            sizeBytes: length, feePerByte: protocolParameters.txFeePerByte, sizeFee: sizeFee,
            fixedFee: protocolParameters.txFeeFixed,
            steps: execSteps, stepsFee: try stepsCost.ceiling.coin("Steps fee"),
            memory: maxMemUnit, memoryFee: try memoryCost.ceiling.coin("Memory fee"),
            executionFee: try (stepsCost + memoryCost).ceiling.coin("Script execution fee"),
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
        
        let (minAda, overflow) = finalizedSize.multipliedReportingOverflow(by: UInt64(protocolParameters.coinsPerUtxoWord))
        guard !overflow else {
            throw CardanoTxBuilderError.valueError("Minimum lovelace of \(finalizedSize) words overflows")
        }
        return minAda
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
        
        let size = constantOverhead + UInt64(try tmpOut.toCBORData().count)
        let (minAda, overflow) = size.multipliedReportingOverflow(by: UInt64(protocolParameters.utxoCostPerByte))
        guard !overflow else {
            throw CardanoTxBuilderError.valueError("Minimum lovelace of \(size) bytes overflows")
        }
        return minAda
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

    /// The size the ledger charges for, in bytes: the signed transaction
    /// without its one-byte validity flag.
    public let sizeBytes: UInt64
    public let feePerByte: UInt64
    /// `sizeBytes × feePerByte`.
    public let sizeFee: UInt64
    /// The fixed part of every fee.
    public let fixedFee: UInt64
    /// Plutus execution steps, and what they cost on their own, rounded up.
    public let steps: UInt64
    public let stepsFee: UInt64
    /// Plutus execution memory, and what it costs on their own, rounded up.
    public let memory: UInt64
    public let memoryFee: UInt64
    /// The script-execution part, as the ledger's `txscriptfee` charges it:
    /// the exact cost of steps plus memory, rounded up once. It can be one
    /// lovelace less than `stepsFee + memoryFee`, which are rounded apart.
    public let executionFee: UInt64
    /// Bytes of reference scripts the transaction uses, and their tiered cost.
    public let referenceScriptBytes: UInt64
    public let referenceScriptTiers: [ReferenceScriptTier]
    public let referenceScriptFee: UInt64
    /// A fixed amount added on top, such as ``TxBuilder/feeBuffer``.
    public var buffer: UInt64 = 0

    /// The whole fee, or `UInt64.max` if the parts overflow. ``checkedTotal()``
    /// throws instead.
    public var total: UInt64 { (try? checkedTotal()) ?? .max }

    /// The whole fee, or an error when the parts don't fit in a `UInt64`.
    public func checkedTotal() throws -> UInt64 {
        var sum: UInt64 = 0
        for part in [sizeFee, fixedFee, executionFee, referenceScriptFee, buffer] {
            let (next, overflow) = sum.addingReportingOverflow(part)
            guard !overflow else {
                throw CardanoTxBuilderError.valueError("Fee overflows: \(sizeFee) + \(fixedFee) + \(executionFee) + \(referenceScriptFee) + \(buffer)")
            }
            sum = next
        }
        return sum
    }
}

/// An exact non-negative fraction, for the ledger's fee arithmetic.
struct Rational {
    let numerator: BigInt
    let denominator: BigInt

    init(_ numerator: BigInt, _ denominator: BigInt = 1) {
        let divisor = numerator.greatestCommonDivisor(with: denominator)
        let d = divisor == 0 ? BigInt(1) : divisor
        self.numerator = numerator / d
        self.denominator = denominator / d
    }

    init(_ interval: NonNegativeInterval) {
        self.init(BigInt(interval.numerator), BigInt(interval.denominator))
    }

    static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator, lhs.denominator * rhs.denominator)
    }

    static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    /// Rounded down; the value is never negative.
    var floor: BigInt { numerator / denominator }

    /// Rounded up; the value is never negative.
    var ceiling: BigInt { (numerator + denominator - 1) / denominator }

    /// The nearest `Double`, for display only.
    var double: Double {
        let whole = numerator / denominator
        let rest = numerator - whole * denominator
        return Double(whole) + Double(rest) / Double(denominator)
    }
}

extension BigInt {
    /// The value as lovelace, or an error naming `what` when it overflows.
    func coin(_ what: String) throws -> UInt64 {
        guard let coin = UInt64(exactly: self) else {
            throw CardanoTxBuilderError.valueError("\(what) of \(self) lovelace overflows")
        }
        return coin
    }
}

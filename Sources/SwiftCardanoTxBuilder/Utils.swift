import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftNcal
import PotentCBOR

// MARK: - Utility Functions

/// Calculate fee for reference scripts.
///
/// - Parameters:
///   - context: A chain context.
///   - scriptsSize: Size of reference scripts in bytes.
/// - Returns: Fee for reference scripts.
/// - Throws: ValueError if scripts size exceeds maximum allowed size
public func tieredReferenceScriptFee(_ context: any ChainContext, scriptsSize: UInt64) async throws -> UInt64 {
    let protocolParameters = try await context.protocolParameters()
    
    if protocolParameters.maxReferenceScriptsSize == nil
        || protocolParameters.minFeeReferenceScripts == nil
    {
        return 0
    }

    let maxSize = protocolParameters.maxReferenceScriptsSize!
    if scriptsSize > maxSize {
        throw CardanoTxBuilderError.valueError(
            "Reference scripts size: \(scriptsSize) exceeds maximum allowed size (\(maxSize))."
        )
    }

    var total: Double = 0.0
    if scriptsSize > 0 {
        var b = protocolParameters.minFeeReferenceScripts!.base!
        let r = ceil(protocolParameters.minFeeReferenceScripts!.range!)
        let m = protocolParameters.minFeeReferenceScripts!.multiplier!

        var remainingSize = scriptsSize

        while remainingSize > UInt64(r) {
            total += b * r
            remainingSize = remainingSize - UInt64(r)
            b = b * m
        }

        total += b * Double(remainingSize)
    }

    return UInt64(ceil(total))
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
public func calculateFee(
    _ context: any ChainContext,
    length: UInt64,
    execSteps: UInt64 = 0,
    maxMemUnit: UInt64 = 0,
    refScriptSize: UInt64 = 0
) async throws -> UInt64 {
    let protocolParameters = try await context.protocolParameters()
    
    let a = ceil(Double(length) * Double(protocolParameters.txFeePerByte))
    let b = ceil(Double(protocolParameters.txFeeFixed))
    let c = ceil(Double(execSteps) * Double(protocolParameters.executionUnitPrices.priceSteps))
    let d = ceil(Double(maxMemUnit) * Double(protocolParameters.executionUnitPrices.priceMemory))
    let e = Double(try await tieredReferenceScriptFee(context, scriptsSize: refScriptSize))
    
    return UInt64(a + b + c + d + e)
}

/// Calculate the maximum transaction fee based on protocol parameters.
///
/// - Parameters:
///   - context: The chain context containing protocol parameters.
///   - refScriptSize: Size of reference scripts in the transaction.
/// - Returns: The maximum transaction fee in lovelace.
public func maxTxFee(_ context: any ChainContext, refScriptSize: UInt64 = 0) async throws -> UInt64 {
    let protocolParameters = try await context.protocolParameters()
    
    return try await calculateFee(
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
public func bundleSize(_ multiAsset: MultiAsset) -> UInt64 {
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
public func minLovelace(
    _ context: any ChainContext,
    output: TransactionOutput? = nil,
    amount: Value? = nil,
    hasDatum: Bool = false
) async throws -> UInt64 {
    if let output = output {
        return try await minLovelacePostAlonzo(output, context)
    } else {
        return try await minLovelacePreAlonzo(amount, context, hasDatum: hasDatum)
    }
}

/// Calculate minimum lovelace a transaction output needs to hold pre-alonzo.
///
/// - Parameters:
///   - amount: Amount from a transaction output.
///   - context: The chain context containing protocol parameters.
///   - hasDatum: Whether the transaction output contains datum hash.
/// - Returns: Minimum required lovelace amount for this transaction output.
public func minLovelacePreAlonzo(
    _ amount: Value?,
    _ context: any ChainContext,
    hasDatum: Bool = false
) async throws -> UInt64 {
    let protocolParameters = try await context.protocolParameters()
    
    if amount == nil || amount?.multiAsset.data.isEmpty ?? true {
        return UInt64(protocolParameters.utxoCostPerByte)
    }

    let bSize = bundleSize(amount!.multiAsset)
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
public func minLovelacePostAlonzo(_ output: TransactionOutput, _ context: any ChainContext) async throws -> UInt64
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

struct Utils {
    
    /// Calculate plutus script data hash
    ///
    /// - Parameters:
    ///   - redeemers: Redeemers to include.
    ///   - datums: Datums to include.
    ///   - costModels: Cost models.
    /// - Returns: Plutus script data hash
    public static func scriptDataHash(
        redeemers: Redeemers? = .list([]),
        datums: [Datum] = [],
        costModels: CostModels? = nil
    ) throws -> ScriptDataHash {
        let costModelsBytes: Data
        let datumBytes: Data
        
        let redeemersIsEmpty: Bool
        switch redeemers {
            case .list(let list):
                redeemersIsEmpty = list.isEmpty
            case .map(let map):
                redeemersIsEmpty = map.count == 0
            case .none:
                redeemersIsEmpty = true
        }
        
        if redeemersIsEmpty {
            costModelsBytes = try CBOREncoder().encode(CBOR.map([:]))
        } else if let costModels = costModels {
            costModelsBytes = try costModels.toCBORData()
        } else {
            let costModels = try CostModels.forScriptDataHash()
            costModelsBytes = try costModels.toCBORData()
        }
        
        if datums.isEmpty {
            datumBytes = Data()
        } else {
            datumBytes = try CBOREncoder().encode(datums)
        }
        
        let redeemerBytes = try redeemers?.toCBORData() ?? Data()
        
        return ScriptDataHash(
            payload: try SwiftNcal.Hash().blake2b(
                data: redeemerBytes + datumBytes + costModelsBytes,
                digestSize: SCRIPT_DATA_HASH_SIZE,
                encoder: RawEncoder.self
            )
        )
    }
}

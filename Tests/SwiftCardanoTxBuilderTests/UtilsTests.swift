import Foundation
import PotentCodables
import SwiftCardanoChain
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxBuilder

// MARK: - Min Lovelace Tests

@Test("Min Lovelace Ada Only")
func testMinLovelaceAdaOnly() async throws {
    let context = MockChainContext()
    let protocolParameters = try await context.protocolParameters()
    let result = try await minLovelacePreAlonzo(Value(coin: 2_000_000), context)
    #expect(result == protocolParameters.utxoCostPerByte)
}

// MARK: - Tests
@Suite("Test MinLoveLaceMultiAsset")
struct TestMinLoveLaceMultiAsset {
    @Test("Min Lovelace Multi Asset 1")
    func testMinLovelaceMultiAsset1() async throws {
        let context = MockChainContext()
        let amount = try Value(
            from: [
                2_000_000,
                [Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [Data().toHex: 1_000_000]],
            ]
        )
        let result = try await minLovelacePreAlonzo(amount, context)
        #expect(result == 1_310_316)
    }

    @Test("Min Lovelace Multi Asset 2")
    func testMinLovelaceMultiAsset2() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [
                        Data([0x31]).toHex: 1_000_000
                    ]
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context)
        #expect(result == 1_344_798)
    }

    @Test("Min Lovelace Multi Asset 3")
    func testMinLovelaceMultiAsset3() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex:
                        [
                            Data([0x31]).toHex: 1_000_000,
                            Data([0x32]).toHex: 2_000_000,
                            Data([0x33]).toHex: 3_000_000,
                        ]
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context)
        #expect(result == 1_448_244)
    }

    @Test("Min Lovelace Multi Asset 4")
    func testMinLovelaceMultiAsset4() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [Data().toHex: 1_000_000],
                    Data(repeating: 0x32, count: SCRIPT_HASH_SIZE).toHex: [Data().toHex: 1_000_000],
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context)
        #expect(result == 1_482_726)
    }

    @Test("Min Lovelace Multi Asset 5")
    func testMinLovelaceMultiAsset5() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [
                        Data([0x31]).toHex: 1_000_000
                    ],
                    Data(repeating: 0x32, count: SCRIPT_HASH_SIZE).toHex: [
                        Data([0x32]).toHex: 1_000_000
                    ],
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context)
        #expect(result == 1_517_208)
    }

    @Test("Min Lovelace Multi Asset 6")
    func testMinLovelaceMultiAsset6() async throws {
        let context = MockChainContext()

        var policy1Assets: [String: Int] = [:]
        var policy2Assets: [String: Int] = [:]
        var policy3Assets: [String: Int] = [:]

        // Create assets for policy 1 (range 1-32)
        for i in 1...32 {
            policy1Assets[Data([UInt8(i)]).toHex] = 1_000_000 * i
        }

        // Create assets for policy 2 (range 32-63)
        for i in 32...63 {
            policy2Assets[Data([UInt8(i)]).toHex] = 1_000_000 * i
        }

        // Create assets for policy 3 (range 64-95)
        for i in 64...95 {
            policy3Assets[Data([UInt8(i)]).toHex] = 1_000_000 * i
        }

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: policy1Assets,
                    Data(repeating: 0x32, count: SCRIPT_HASH_SIZE).toHex: policy2Assets,
                    Data(repeating: 0x33, count: SCRIPT_HASH_SIZE).toHex: policy3Assets,
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context)
        #expect(result == 6_896_400)
    }

    @Test("Min Lovelace Multi Asset 7")
    func testMinLovelaceMultiAsset7() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [Data().toHex: 1_000_000]],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context, hasDatum: true)
        #expect(result == 1_655_136)
    }

    @Test("Min Lovelace Multi Asset 8")
    func testMinLovelaceMultiAsset8() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [
                        Data(repeating: 0x31, count: 32).toHex: 1_000_000,
                        Data(repeating: 0x32, count: 32).toHex: 1_000_000,
                        Data(repeating: 0x33, count: 32).toHex: 1_000_000,
                    ]
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context, hasDatum: true)
        #expect(result == 2_172_366)
    }

    @Test("Min Lovelace Multi Asset 9")
    func testMinLovelaceMultiAsset9() async throws {
        let context = MockChainContext()

        let amount = try Value(
            from: [
                2_000_000,
                [
                    Data(repeating: 0x31, count: SCRIPT_HASH_SIZE).toHex: [Data().toHex: 1_000_000],
                    Data(repeating: 0x32, count: SCRIPT_HASH_SIZE).toHex: [Data().toHex: 1_000_000],
                ],
            ]
        )

        let result = try await minLovelacePreAlonzo(amount, context, hasDatum: true)
        #expect(result == 1_827_546)
    }
}

// MARK: - ScriptDataHash Tests
@Suite("Test ScriptDataHash")
struct TestScriptDataHash {
    
    @Test("Script Data Hash")
    func testScriptDataHash() throws {
        let unit = SwiftCardanoCore.Unit()
        let redeemers: Redeemers<SwiftCardanoCore.Unit> = .list([
            Redeemer<SwiftCardanoCore.Unit>(
                tag: .spend,
                index: 0,
                data: unit,
                exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
            )
        ])
        
        let result = try Utils.scriptDataHash(
            redeemers: redeemers,
            datums: [.plutusData(unit)]
        )
        let scriptHash = try ScriptDataHash(
            from:
                    .string(
                        "032d812ee0731af78fe4ec67e4d30d16313c09e6fb675af28f825797e8b5621d"
                    )
        )
        
        #expect(result.payload.toHex == scriptHash.payload.toHex)
    }
    
    @Test("Script Data Hash with Datum Only")
    func testScriptDataHashDatumOnly() throws {
        let unit = SwiftCardanoCore.Unit()
        
        let result = try Utils<Never>.scriptDataHash(
            datums: [.plutusData(unit)],
        )
        let scriptHash = try ScriptDataHash(
            from: .string("2f50ea2546f8ce020ca45bfcf2abeb02ff18af2283466f888ae489184b3d2d39")
        )
        
        #expect(result.payload.toHex == scriptHash.payload.toHex)
    }
    
    @Test("Script Data Hash with Redeemer Only")
    func testScriptDataHashRedeemerOnly() throws {
        let result = try Utils<Never>.scriptDataHash(
            redeemers: .list([])
        )
        let scriptHash = try ScriptDataHash(
            from: .string("a88fe2947b8d45d1f8b798e52174202579ecf847b8f17038c7398103df2d27b0")
        )
        
        #expect(result.payload.toHex == scriptHash.payload.toHex)
    }
}

// MARK: - Tiered Reference Script Fee Tests
@Suite("TieredReferenceScriptFee Tests")
struct TieredReferenceScriptFeeTests {
    
    @Test("Tiered Reference Script Fee")
    func testTieredReferenceScriptFee() async throws {
        let context = MockChainContext()

        let result = try await tieredReferenceScriptFee(context, scriptsSize: 80 * 1024)
        #expect(result == 4_489_380)
    }

    @Test("Tiered Reference Script Fee Exceeds Max Size")
    func testTieredReferenceScriptFeeExceedsMaxSize() async throws {
        let context = MockChainContext()

        await #expect(
            throws: CardanoTxBuilderError.valueError(
                "Reference scripts size: 204801 exceeds maximum allowed size (204800).")
        ) {
            _ = try await tieredReferenceScriptFee(context, scriptsSize: 204801)
        }
    }

    @Test("Tiered Reference Script Fee No Params")
    func testTieredReferenceScriptFeeNoParams() async throws {
        let context = MockChainContext(
            protocolParameters: ProtocolParameters(
                collateralPercentage: 0,
                coinsPerUtxoWord: 0,
                committeeMaxTermLength: 0,
                committeeMinSize: 0,
                costModels: ProtocolParametersCostModels(
                    PlutusV1: [],
                    PlutusV2: [],
                    PlutusV3: []
                ),
                dRepActivity: 0,
                dRepDeposit: 0,
                dRepVotingThresholds: DRepVotingThresholds(
                    committeeNoConfidence: 0,
                    committeeNormal: 0,
                    hardForkInitiation: 0,
                    motionNoConfidence: 0,
                    ppEconomicGroup: 0,
                    ppGovGroup: 0,
                    ppNetworkGroup: 0,
                    ppTechnicalGroup: 0,
                    treasuryWithdrawal: 0,
                    updateToConstitution: 0
                ),
                executionUnitPrices: ExecutionUnitPrices(
                    priceMemory: 0,
                    priceSteps: 0
                ),
                govActionDeposit: 0,
                govActionLifetime: 0,
                maxBlockBodySize: 0,
                maxBlockExecutionUnits: ProtocolParametersExecutionUnits(
                    memory: 0,
                    steps: 0
                ),
                maxBlockHeaderSize: 0,
                maxCollateralInputs: 0,
                maxTxExecutionUnits: ProtocolParametersExecutionUnits(
                    memory: 0,
                    steps: 0
                ),
                maxTxSize: 0,
                maxValueSize: 0,
                minPoolCost: 0,
                monetaryExpansion: 0,
                poolPledgeInfluence: 0,
                poolRetireMaxEpoch: 0,
                poolVotingThresholds: ProtocolParametersPoolVotingThresholds(
                    committeeNoConfidence: 0,
                    committeeNormal: 0,
                    hardForkInitiation: 0,
                    motionNoConfidence: 0,
                    ppSecurityGroup: 0
                ),
                protocolVersion: ProtocolParametersProtocolVersion(
                    major: 0,
                    minor: 0
                ),
                stakeAddressDeposit: 0,
                stakePoolDeposit: 0,
                stakePoolTargetNum: 0,
                treasuryCut: 0,
                txFeeFixed: 0,
                txFeePerByte: 0,
                utxoCostPerByte: 0
            ))

        let result = try await tieredReferenceScriptFee(context, scriptsSize: 100)
        #expect(result == 0)
    }
}

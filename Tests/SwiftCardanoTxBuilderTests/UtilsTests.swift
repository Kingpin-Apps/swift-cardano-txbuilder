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

@Test("Script Data Hash")
func testScriptDataHash() throws {
    let unit = SwiftCardanoCore.Unit()
    let redeemers = Redeemers.list([
        Redeemer(
            tag: .spend,
            index: 0,
            data: try AnyValue.Encoder().encode(unit),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
    ])

    let result = try scriptDataHash(
        redeemers: redeemers,
        datums: [.bytes(unit.toCBOR())]
    )
    let scriptHash = try ScriptDataHash(
        from: "032d812ee0731af78fe4ec67e4d30d16313c09e6fb675af28f825797e8b5621d"
    )
    print("Script Hash: \(scriptHash)")
    #expect(result.payload.toHex == scriptHash.payload.toHex)
}

//@Suite("Utils Tests", .disabled())
//struct UtilsTests {
//
//    // MARK: - Script Data Hash Tests
//

//
//    @Test("Script Data Hash Datum Only")
//    func testScriptDataHashDatumOnly() throws {
//        let unit = Unit()
//        let result = try scriptDataHash(redeemers: Redeemers.list([]), datums: [unit])
//        #expect(
//            result.payload.hexString
//                == "2f50ea2546f8ce020ca45bfcf2abeb02ff18af2283466f888ae489184b3d2d39")
//    }
//
//    // MARK: - Tiered Reference Script Fee Tests
//
//    @Test("Tiered Reference Script Fee")
//    func testTieredReferenceScriptFee() async throws {
//        let minFeeReferenceScripts = MinFeeReferenceScripts(
//            base: 44,
//            range: 25600,
//            multiplier: 1.2
//        )
//        let context = MockChainContext(
//            protocolParameters: MockProtocolParameters(
//                maxReferenceScriptsSize: 200 * 1024,
//                minFeeReferenceScripts: minFeeReferenceScripts
//            )
//        )
//
//        let result = try await tieredReferenceScriptFee(context, scriptsSize: 80 * 1024)
//        #expect(result == 4_489_380)
//    }
//
//    @Test("Tiered Reference Script Fee Exceeds Max Size")
//    func testTieredReferenceScriptFeeExceedsMaxSize() async throws {
//        let minFeeReferenceScripts = MinFeeReferenceScripts(
//            base: 10,
//            range: 100,
//            multiplier: 1.1
//        )
//        let context = MockChainContext(
//            protocolParameters: MockProtocolParameters(
//                maxReferenceScriptsSize: 1000,
//                minFeeReferenceScripts: minFeeReferenceScripts
//            )
//        )
//
//        await #expect(
//            throws: CardanoTxBuilderError.valueError(
//                "Warning: Reference scripts size: 1001 exceeds maximum allowed size (1000).")
//        ) {
//            _ = try await tieredReferenceScriptFee(context, scriptsSize: 1001)
//        }
//    }
//
//    @Test("Tiered Reference Script Fee No Params")
//    func testTieredReferenceScriptFeeNoParams() async throws {
//        let context = MockChainContext(
//            protocolParameters: MockProtocolParameters(
//                maxReferenceScriptsSize: nil,
//                minFeeReferenceScripts: nil
//            )
//        )
//
//        let result = try await tieredReferenceScriptFee(context, scriptsSize: 100)
//        #expect(result == 0)
//    }
//}

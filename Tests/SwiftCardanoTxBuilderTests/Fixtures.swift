import Foundation
import Testing

import SwiftCardanoChain
import SwiftCardanoCore

@testable import SwiftCardanoTxBuilder

// MARK: - Mock Classes

class MockChainContext: ChainContext {
    private var _protocolParameters: ProtocolParameters?
    
    var protocolParameters: () async throws -> SwiftCardanoCore.ProtocolParameters {
        
        if self._protocolParameters == nil {
            let protocolParametersJSON = try! getFilePath(
                forResource: protocolParametersJSONFilePath.forResource,
                ofType: protocolParametersJSONFilePath.ofType,
                inDirectory: protocolParametersJSONFilePath.inDirectory
            )
            
            self._protocolParameters = try! ProtocolParameters.load(from: protocolParametersJSON!)
        }
        
        return {
            self._protocolParameters!
        }
    }

    var genesisParameters: () async throws -> SwiftCardanoCore.GenesisParameters {
        return {
            GenesisParameters(
                activeSlotsCoefficient: Double(1000),
                epochLength: 21600,
                maxKesEvolutions: 90,
                maxLovelaceSupply: 45_000_000_000,
                networkId: "testnet",
                networkMagic: 42,
                securityParam: 2160,
                slotLength: 1,
                slotsPerKesPeriod: 1_200,
                systemStart: ISO8601DateFormatter().date(from: "2017-09-23T21:44:51Z")!,
                updateQuorum: 5
            )
        }
    }

    var network: SwiftCardanoCore.Network {
        .testnet
    }

    var epoch: () async throws -> Int {
        return {
            100
        }
    }

    var lastBlockSlot: () async throws -> Int {
        return {
            100
        }
    }


    func utxos(address: SwiftCardanoCore.Address) async throws -> [SwiftCardanoCore.UTxO] {
        return []
    }

    func submitTxCBOR(cbor: Data) async throws -> String {
        return ""
    }

    func evaluateTxCBOR(cbor: Data) async throws -> [String : SwiftCardanoCore.ExecutionUnits] {
        return [:]
    }

    func stakeAddressInfo(address: SwiftCardanoCore.Address) async throws -> [SwiftCardanoChain.StakeAddressInfo] {
        return []
    }

    init() {}
    
    init(protocolParameters: ProtocolParameters) {
        self._protocolParameters = protocolParameters
    }
}

// MARK - Helper Functions

func getFilePath(forResource: String, ofType: String, inDirectory: String) throws -> String? {
    guard let filePath = Bundle.module.path(
        forResource: forResource,
        ofType: ofType,
        inDirectory: inDirectory) else {
        Issue.record("File not found: \(forResource).\(ofType)")
        try #require(Bool(false))
        return nil
    }
    return filePath
}


// MARK: - Protocol Parameters Path
let protocolParametersJSONFilePath = (
    forResource: "protocol-parameters",
    ofType: "json",
    inDirectory: "data"
)

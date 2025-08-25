import Foundation
import Testing

import SwiftCardanoChain
import SwiftCardanoCore

@testable import SwiftCardanoTxBuilder

// MARK: - Mock Classes

class MockChainContext: ChainContext {
    typealias ReedemerType = Never

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
        let txIn1 = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 1, count: 32)),
            index: 0
        )
        let txIn2 = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 2, count: 32)),
            index: 1
        )
        
        let txOut1 = TransactionOutput(
            address: address,
            amount: Value(coin: 500_000_000)
        )
        
        let policyId = PolicyID(payload: Data(repeating: 1, count: 28))
        let multiAsset = MultiAsset([
            policyId: Asset([
                try AssetName(payload: Data("Token1".utf8)): 1,
                try AssetName(payload: Data("Token2".utf8)): 2
            ])
        ])
        let txOut2 = TransactionOutput(
            address: address,
            amount: Value(coin: 600_000_000, multiAsset: multiAsset)
        )
        
        return [
            UTxO(input: txIn1, output: txOut1),
            UTxO(input: txIn2, output: txOut2)
        ]
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
    
    init(protocolParameters: ProtocolParameters?) {
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

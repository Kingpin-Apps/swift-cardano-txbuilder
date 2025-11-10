import Foundation
import Testing
import Network

import Logging
import SwiftCardanoChain
import SwiftCardanoCore

@testable import SwiftCardanoTxBuilder

// MARK: - Mock Classes

class MockChainContext: ChainContext {
    var name: String = "MockChainContext"

    public var _protocolParameters: ProtocolParameters?

    public var _utxos: [UTxO]?
    
    public var _stakeAddressInfo: [StakeAddressInfo]?
    
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

    var networkId: SwiftCardanoCore.NetworkId {
        .testnet
    }

    var epoch: () async throws -> Int {
        return {
            300
        }
    }

    var lastBlockSlot: () async throws -> Int {
        return {
            2000
        }
    }


    func utxos(address: SwiftCardanoCore.Address) async throws -> [SwiftCardanoCore.UTxO] {
        if _utxos != nil {
            return _utxos!.filter { $0.output.address == address }
        }
        
        let txIn1 = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0x31, count: 32)), // ASCII "1" = 0x31
            index: 0
        )
        let txIn2 = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0x32, count: 32)), // ASCII "2" = 0x32
            index: 1
        )
        
        let txOut1 = TransactionOutput(
            address: address,
            amount: Value(coin: 5_000_000)
        )
        
        let policyId = PolicyID(payload: Data(repeating: 0x31, count: 28))
        let multiAsset = MultiAsset([
            policyId: Asset([
                try AssetName(payload: Data("Token1".utf8)): 1,
                try AssetName(payload: Data("Token2".utf8)): 2
            ])
        ])
        let txOut2 = TransactionOutput(
            address: address,
            amount: Value(coin: 6_000_000, multiAsset: multiAsset)
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
        // Return mock execution units for testing
        return [
            "spend:0": ExecutionUnits(mem: 399_882, steps: 175_940_720)
        ]
    }

    func stakeAddressInfo(address: SwiftCardanoCore.Address) async throws -> [StakeAddressInfo] {
        if let injected = _stakeAddressInfo {
            return injected
        }
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

// MARK: - Key File Paths
let paymentVerificationKeyFilePath = (
    forResource: "test.payment",
    ofType: "vkey",
    inDirectory: "data"
)
let paymentSigningKeyFilePath = (
    forResource: "test.payment",
    ofType: "skey",
    inDirectory: "data"
)

var paymentVerificationKey: PaymentVerificationKey? {
    do {
        let keyPath = try getFilePath(
            forResource: paymentVerificationKeyFilePath.forResource,
            ofType: paymentVerificationKeyFilePath.ofType,
            inDirectory: paymentVerificationKeyFilePath.inDirectory
        )
        return try PaymentVerificationKey.load(from: keyPath!)
    } catch {
        return nil
    }
}

var paymentSigningKey: PaymentSigningKey? {
    do {
        let keyPath = try getFilePath(
            forResource: paymentSigningKeyFilePath.forResource,
            ofType: paymentSigningKeyFilePath.ofType,
            inDirectory: paymentSigningKeyFilePath.inDirectory
        )
        return try PaymentSigningKey.load(from: keyPath!)
    } catch {
        return nil
    }
}

let stakeVerificationKeyFilePath = (
    forResource: "test.stake",
    ofType: "vkey",
    inDirectory: "data"
)
let stakeSigningKeyFilePath = (
    forResource: "test.stake",
    ofType: "skey",
    inDirectory: "data"
)

var stakeVerificationKey: StakeVerificationKey? {
    do {
        let keyPath = try getFilePath(
            forResource: stakeVerificationKeyFilePath.forResource,
            ofType: stakeVerificationKeyFilePath.ofType,
            inDirectory: stakeVerificationKeyFilePath.inDirectory
        )
        return try StakeVerificationKey.load(from: keyPath!)
    } catch {
        return nil
    }
}

var stakeSigningKey: StakeSigningKey? {
    do {
        let keyPath = try getFilePath(
            forResource: stakeSigningKeyFilePath.forResource,
            ofType: stakeSigningKeyFilePath.ofType,
            inDirectory: stakeSigningKeyFilePath.inDirectory
        )
        return try StakeSigningKey.load(from: keyPath!)
    } catch {
        return nil
    }
}

var poolParams: PoolParams {
    return PoolParams(
        poolOperator: PoolKeyHash(payload: Data(repeating: 0x31, count: POOL_KEY_HASH_SIZE)),
        vrfKeyHash: VrfKeyHash(
            payload: Data(repeating: 0x31, count: VRF_KEY_HASH_SIZE)
        ),
        pledge: 100_000_000,
        cost: 340_000_000,
        margin: UnitInterval(numerator: 1, denominator: 50),
        rewardAccount: RewardAccountHash(payload: Data(repeating: 0x31, count: REWARD_ACCOUNT_HASH_SIZE)),
        poolOwners: .list([
            VerificationKeyHash(payload: Data(repeating: 0x31, count: VERIFICATION_KEY_HASH_SIZE))
        ]),
        relays: [
            .singleHostAddr(
                SingleHostAddr(
                    port: 3001,
                    ipv4: IPv4Address("192.168.0.1")!,
                    ipv6: IPv6Address("::1")!
                )
            ),
            .singleHostName(
                SingleHostName(
                    port: 3001,
                    dnsName: "relay1.example.com"
                )
            ),
            .multiHostName(MultiHostName(dnsName: "relay1.example.com"))
            
        ],
        poolMetadata: try! PoolMetadata(
            url: try! Url("https://meta1.example.com"),
            poolMetadataHash: PoolMetadataHash(payload: Data(repeating: 0x31, count: POOL_METADATA_HASH_SIZE))
        )
    )
}

/// Pool operator derived from poolParams for delegation tests
var poolOperator: PoolOperator {
    return PoolOperator(poolKeyHash: poolParams.poolOperator)
}

/// DRep credential fixture using deterministic key hash for governance tests
var drepCredential: DRepCredential {
    // Use deterministic bytes for test DRep credential (derived from repeating pattern)
    return DRepCredential(
        credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x42, count: VERIFICATION_KEY_HASH_SIZE)))
    )
}

/// Governance anchor fixture with test URL and metadata hash
var anchor: Anchor {
    return Anchor(
        anchorUrl: try! Url("https://example.com/governance-metadata.json"),
        anchorDataHash: AnchorDataHash(payload: Data(repeating: 0x51, count: 32))
    )
}

/// DRep value using the drepCredential for delegation tests
var drep: DRep {
    return DRep(credential: try! DRepType(from: drepCredential))
}

/// Committee cold credential fixture using deterministic key hash
var committeeColdCredential: CommitteeColdCredential {
    return CommitteeColdCredential(
        credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x61, count: VERIFICATION_KEY_HASH_SIZE)))
    )
}

/// Committee hot credential fixture using deterministic key hash
var committeeHotCredential: CommitteeHotCredential {
    return CommitteeHotCredential(
        credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x62, count: VERIFICATION_KEY_HASH_SIZE)))
    )
}
    

func captureStdout(_ block: () async throws -> Void) async throws -> String {
    let pipe = Pipe()
    let originalStdOut = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    try await block()

    // Flush and restore stdout before closing the pipe's write end
    fflush(stdout)
    dup2(originalStdOut, STDOUT_FILENO)
    close(originalStdOut)

    // Now close the write end so the read end receives EOF
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func captureStderr(_ block: () async throws -> Void) async throws -> String {
    let pipe = Pipe()
    let originalStdErr = dup(STDERR_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

    try await block()

    fflush(stderr)
    dup2(originalStdErr, STDERR_FILENO)
    close(originalStdErr)

    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

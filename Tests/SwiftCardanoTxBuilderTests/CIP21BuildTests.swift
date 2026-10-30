import Foundation
import SwiftCardanoCIP21
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxBuilder

/// Building for hardware wallets (CIP-21): the body is written as they ask
/// before the fee is sized, so the fee covers the bytes that are signed.
@Suite("Building for hardware wallets (CIP-21)")
struct CIP21BuildTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    func hash(_ byte: UInt8) -> VerificationKeyHash { VerificationKeyHash(payload: Data(repeating: byte, count: 28)) }

    func builder(_ certificates: [Certificate], cip21: Bool = true) throws -> TxBuilder {
        let txIn = TransactionInput(transactionId: TransactionId(payload: Data(repeating: 0x32, count: 32)), index: 2)
        let txOut = TransactionOutput(address: try Address(from: .string(sender)), amount: Value(coin: 505_000_000))
        let builder = TxBuilder(context: MockChainContext())
        builder.addInput(UTxO(input: txIn, output: txOut))
        builder.certificates = certificates
        builder.cip21Compatible = cip21
        return builder
    }

    func registration() throws -> Certificate {
        .register(try Register(stakeCredential: StakeCredential(credential: .verificationKeyHash(hash(0x5A))), coin: 2_000_000))
    }

    /// The transaction `builder` built, signed by `signers` placeholder keys
    /// with the witnesses as a tagged set.
    func signed(_ body: TransactionBody, _ builder: TxBuilder, signers: Int) throws -> Data {
        var witnesses = try builder.buildWitnessSet()
        witnesses.vkeyWitnesses = .nonEmptyOrderedSet(NonEmptyOrderedSet(try (1...signers).map { index in
            VerificationKeyWitness(
                vkey: .verificationKey(try VerificationKey(payload: Data(repeating: UInt8(index), count: 32))),
                signature: Data(repeating: UInt8(index), count: 64)
            )
        }))
        return try Transaction(transactionBody: body, transactionWitnessSet: witnesses, valid: true).toCBORData()
    }

    @Test("The body is written as CIP-21 asks, and the fee covers it once signed")
    func registrationBuilds() async throws {
        let builder = try builder([registration()])
        let body = try await builder.build(changeAddress: try Address(from: .string(sender)))
        let bytes = try body.toCBORData()
        #expect(try CIP21.compatibleBody(bytes) == bytes)

        let signed = try signed(body, builder, signers: 2)
        #expect(try CIP21.report(signed).isCompatible)
        let parameters = try await MockChainContext().protocolParameters()
        // Exactly what the node asks: sized without the validity flag, as the
        // ledger sizes it.
        let minimum = UInt64(parameters.txFeeFixed) + UInt64(parameters.txFeePerByte) * UInt64(signed.count - 1)
        #expect(body.fee == minimum)
        #expect((try await builder.estimateFeeBreakdown()).sizeBytes == UInt64(signed.count - 1))
    }

    @Test("A pool registration's owners are written as a tagged set, and its fee pays for the tag")
    func poolOwners() async throws {
        let params = PoolParams(
            poolOperator: PoolKeyHash(payload: Data(repeating: 1, count: 28)),
            vrfKeyHash: VrfKeyHash(payload: Data(repeating: 9, count: 32)),
            pledge: 1_000_000, cost: 340_000_000,
            margin: UnitInterval(numerator: 1, denominator: 50),
            rewardAccount: RewardAccountHash(payload: Data([0xE0]) + Data(repeating: 2, count: 28)),
            poolOwners: .list([hash(2), hash(3)]),
            relays: nil, poolMetadata: nil
        )
        func build(cip21: Bool) async throws -> TransactionBody {
            let builder = try builder([.poolRegistration(PoolRegistration(poolParams: params))], cip21: cip21)
            builder.initialStakePoolRegistration = true
            return try await builder.build(changeAddress: try Address(from: .string(sender)))
        }
        let plain = try await build(cip21: false)
        let compatible = try await build(cip21: true)
        // The owners' tag is three bytes more to pay for.
        #expect(compatible.fee == plain.fee + 3 * 44)
        #expect(try compatible.toCBORData().toHex.contains("d9010282581c"))
        let report = try CIP21.report(Data([0x84]) + (try compatible.toCBORData()) + Data([0xA0, 0xF5, 0xF6]))
        #expect(report.mode == .poolRegistration)
        #expect(report.isCompatible, "\(report.findings)")
    }

    @Test("A certificate hardware wallets refuse fails the build, and builds without the flag")
    func refused() async throws {
        let certificate = Certificate.stakeRegisterDelegate(try StakeRegisterDelegate(
            stakeCredential: StakeCredential(credential: .verificationKeyHash(hash(0x5A))),
            poolKeyHash: PoolKeyHash(payload: Data(repeating: 0xAB, count: 28)),
            coin: 2_000_000
        ))
        let change = try Address(from: .string(sender))
        await #expect(throws: CardanoTxBuilderError.self) {
            _ = try await builder([certificate]).build(changeAddress: change)
        }
        _ = try await builder([certificate], cip21: false).build(changeAddress: change)
    }

    @Test("Without the flag, the body is written as before")
    func unchanged() async throws {
        let plain = try builder([registration()], cip21: false)
        let compatible = try builder([registration()])
        let change = try Address(from: .string(sender))
        let plainBody = try await plain.build(changeAddress: change)
        let compatibleBody = try await compatible.build(changeAddress: change)
        // Certificates are a tagged set either way, so for this transaction
        // the two are the same.
        #expect(try plainBody.toCBORData() == compatibleBody.toCBORData())
    }
}

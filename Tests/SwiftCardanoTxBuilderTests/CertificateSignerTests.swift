import Foundation
import SwiftCardanoCore
import Testing
@testable import SwiftCardanoTxBuilder

/// The keys a certificate needs signatures from, which size the fee.
@Suite("Certificate signers")
struct CertificateSignerTests {
    func hash(_ byte: UInt8) -> VerificationKeyHash { VerificationKeyHash(payload: Data(repeating: byte, count: 28)) }

    func signers(_ certificate: Certificate) -> Set<VerificationKeyHash> {
        let builder = TxBuilder(context: MockChainContext())
        builder.certificates = [certificate]
        return builder.certificateVkeyHashes()
    }

    @Test("A pool registration is signed by the cold key and every owner, not the VRF key")
    func poolRegistration() throws {
        let params = PoolParams(
            poolOperator: PoolKeyHash(payload: Data(repeating: 1, count: 28)),
            vrfKeyHash: VrfKeyHash(payload: Data(repeating: 9, count: 32)),
            pledge: 1_000_000, cost: 170_000_000,
            margin: UnitInterval(numerator: 1, denominator: 20),
            rewardAccount: RewardAccountHash(payload: Data([0xE0]) + Data(repeating: 2, count: 28)),
            poolOwners: .list([hash(2), hash(3)]),
            relays: nil, poolMetadata: nil
        )
        #expect(signers(.poolRegistration(PoolRegistration(poolParams: params))) == [hash(1), hash(2), hash(3)])
    }

    @Test("Retiring or updating a DRep, and committee key certificates, are signed by their key")
    func governanceCertificates() {
        let key = CredentialType.verificationKeyHash(hash(5))
        #expect(signers(.unRegisterDRep(UnregisterDRep(drepCredential: DRepCredential(credential: key), coin: 500_000_000))) == [hash(5)])
        #expect(signers(.updateDRep(UpdateDRep(drepCredential: DRepCredential(credential: key), anchor: nil))) == [hash(5)])
        let cold = CommitteeColdCredential(credential: key)
        #expect(signers(.authCommitteeHot(AuthCommitteeHot(
            committeeColdCredential: cold, committeeHotCredential: CommitteeHotCredential(credential: .verificationKeyHash(hash(6)))
        ))) == [hash(5)])
        #expect(signers(.resignCommitteeCold(ResignCommitteeCold(committeeColdCredential: cold))) == [hash(5)])
    }
}

/// The fee is sized from the body as it is written: sets tagged one way,
/// and a placeholder witness for every key the certificates need.
@Suite("Certificate fee sizing")
struct CertificateFeeSizingTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    func builder() throws -> TxBuilder {
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: { sequence.removeFirst() })
        let builder = TxBuilder(context: MockChainContext(), utxoSelectors: [selector])
        try builder.addInputAddress(.string(sender))
        let stake = CredentialType.verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x5A, count: 28)))
        builder.certificates = [.register(Register(stakeCredential: StakeCredential(credential: stake), coin: 2_000_000))]
        return builder
    }

    /// A witness that is the size of a real one.
    func witness(_ index: UInt8) throws -> VerificationKeyWitness {
        VerificationKeyWitness(
            vkey: .verificationKey(try VerificationKey(payload: Data(repeating: index, count: 32))),
            signature: Data(repeating: index, count: 64)
        )
    }

    @Test("Certificates are written as a tagged set, like the inputs")
    func taggedSet() async throws {
        let builder = try builder()
        let body = try await builder.build(changeAddress: try Address(from: .string(sender)))
        guard case .nonEmptyOrderedSet? = body.certificates else {
            Issue.record("Certificates are \(String(describing: body.certificates))")
            return
        }
        let bytes = try body.toCBORData()
        // Field 4, then tag 258, then a one-element array.
        #expect(bytes.toHex.contains("04d9010281"))
        // Written back by the ledger types, the body keeps its bytes.
        #expect(try TransactionBody.fromCBOR(data: bytes).toCBORData() == bytes)
    }

    @Test("The fee covers the transaction once every needed key has signed, with witnesses as a tagged set")
    func feeCoversSigned() async throws {
        let builder = try builder()
        let body = try await builder.build(changeAddress: try Address(from: .string(sender)))
        let breakdown = try await builder.estimateFeeBreakdown()
        // The input's key and the certificate's stake key.
        var witnesses = try builder.buildWitnessSet()
        witnesses.vkeyWitnesses = .nonEmptyOrderedSet(NonEmptyOrderedSet([try witness(1), try witness(2)]))
        let signed = try Transaction(transactionBody: body, transactionWitnessSet: witnesses, valid: true).toCBORData()
        // The ledger sizes a transaction without its one-byte validity flag,
        // and so does the builder: the fee is the node's minimum, exactly.
        #expect(breakdown.sizeBytes == UInt64(signed.count - 1), "Sized for \(breakdown.sizeBytes) bytes; signed, the ledger counts \(signed.count - 1).")
        let parameters = try await MockChainContext().protocolParameters()
        let minimum = UInt64(parameters.txFeeFixed) + UInt64(parameters.txFeePerByte) * UInt64(signed.count - 1)
        #expect(body.fee == minimum)
    }
}

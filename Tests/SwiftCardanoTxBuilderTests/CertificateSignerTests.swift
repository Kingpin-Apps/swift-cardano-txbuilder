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

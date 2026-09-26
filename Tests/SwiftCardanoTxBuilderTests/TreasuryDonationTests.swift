import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
@testable import SwiftCardanoTxBuilder

@Suite("Treasury donation")
struct TreasuryDonationTests {
    let sender = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    @Test("A donation comes out of the change, so the value balances")
    func donationBalances() async throws {
        var sequence: [Int] = [0, 0]
        let selector = RandomImproveMultiAsset(randomGenerator: { sequence.removeFirst() })
        let builder = TxBuilder(context: MockChainContext(), utxoSelectors: [selector])
        let senderAddress = try Address(from: .string(sender))
        try builder.addInputAddress(.string(sender)).addOutput(
            TransactionOutput(address: senderAddress, amount: Value(coin: 500_000))
        )
        try builder.addTreasuryDonation(1_000_000)

        let body = try await builder.build(changeAddress: senderAddress)
        // The mock UTxO the builder picks holds 5 ada.
        let out = body.outputs.reduce(Int64(0)) { $0 + $1.amount.coin }
        #expect(out + Int64(body.fee) + 1_000_000 == 5_000_000)
        #expect(body.treasuryDonation == PositiveCoin(1_000_000))
    }
}

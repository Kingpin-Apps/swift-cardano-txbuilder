# Transaction Helpers Quick Reference

A comprehensive guide to all transaction helper methods available in SwiftCardanoTxBuilder.

## Overview

SwiftCardanoTxBuilder provides convenient helper methods via `txBuilder.transactions` that simplify common transaction patterns. Each helper automatically handles UTxO selection, certificate creation, fee calculation, and transaction building.

### Prerequisites

All examples assume you have initialized a chain context and transaction builder:

```swift
import SwiftCardanoTxBuilder
import SwiftCardanoCore
import SwiftCardanoChain

let chainContext = try await BlockFrostChainContext(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder(context: chainContext)
```

### Key Loading Pattern

Most helpers require signing keys wrapped in `SigningKeyType`:

```swift
let paymentSKey = try PaymentSigningKey.load(from: "path/to/payment.skey")
let stakeSKey = try StakeSigningKey.load(from: "path/to/stake.skey")

let signingKeys: [SigningKeyType] = [
    .signingKey(paymentSKey),
    .signingKey(stakeSKey)
]
```

**Note:** Pass `nil` or `[]` for `signingKeys` to get an unsigned transaction.

## Stake Address Operations

### Register Stake Address

Register a new stake address on the blockchain:

```swift
let stakeVKey = try StakeVerificationKey.load(from: "path/to/stake.vkey")
let feePaymentAddress = try Address(from: .string("addr_test1vr..."))

let tx = try await txBuilder.transactions.stakeAddressRegistration(
    stakeVerificationKey: stakeVKey,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

**Automatically handles:**
- Verifies stake address is not already registered
- Creates `StakeRegistration` certificate
- Includes deposit requirement in fee calculation

### Deregister Stake Address

Deregister a stake address and reclaim the deposit:

```swift
let tx = try await txBuilder.transactions.stakeAddressDeregistration(
    stakeVerificationKey: stakeVKey,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

**Automatically handles:**
- Verifies stake address is registered
- Creates `StakeDeregistration` certificate
- Returns the stake address deposit

## Stake Delegation

### Delegate to Stake Pool

Delegate a registered stake address to a pool:

```swift
let poolKeyHash = try PoolKeyHash(from: .string("pool1..."))
let poolOperator = PoolOperator(poolKeyHash: poolKeyHash)

let tx = try await txBuilder.transactions.stakeDelegation(
    stakeVerificationKey: stakeVKey,
    poolOperator: poolOperator,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

**Automatically handles:**
- Verifies stake address is registered
- Creates `StakeDelegation` certificate
- No additional deposit required (can change delegation freely)

### Register and Delegate (Combined)

Register and delegate in a single transaction (more efficient):

```swift
let tx = try await txBuilder.transactions.stakeAddressRegistrationAndDelegation(
    stakeVerificationKey: stakeVKey,
    poolOperator: poolOperator,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

**Automatically handles:**
- Verifies stake address is not already registered
- Creates `StakeRegisterDelegate` certificate
- Includes deposit in single transaction
- Saves on transaction fees vs. separate operations

## Rewards

### Withdraw Staking Rewards

Withdraw accumulated rewards from a stake address:

```swift
// Option 1: Withdraw to specific address
let receiverAddress = try Address(from: .string("addr_test1vq..."))

let tx = try await txBuilder.transactions.withdrawRewards(
    from: stakeVKey,
    to: receiverAddress,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

// Option 2: Merge with change (to: nil)
let tx = try await txBuilder.transactions.withdrawRewards(
    from: stakeVKey,
    to: nil,  // Rewards merged with change to feePaymentAddress
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

**Automatically handles:**
- Queries stake address for available rewards
- Creates withdrawal with full reward balance
- Routes rewards to specified address or merges with change

## Governance (CIP-1694)

### Delegate Vote to DRep

Delegate voting power to a Delegated Representative:

```swift
let drepCredential = DRepCredential(
    credential: .verificationKeyHash(
        try VerificationKeyHash(from: .string("drep1..."))
    )
)
let drep = try DRep(credential: DRepType(from: drepCredential))

let tx = try await txBuilder.transactions.voteDelegation(
    stakeVerificationKey: stakeVKey,
    drep: drep,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

**Special DRep values:**
```swift
// Abstain from voting
let abstainDrep = DRep(credential: .abstain)

// Vote "no confidence"
let noConfidenceDrep = DRep(credential: .noConfidence)
```

### Register and Delegate Vote

Register stake address and delegate vote in one transaction:

```swift
let tx = try await txBuilder.transactions.stakeAddressRegistrationAndVoteDelegation(
    stakeVerificationKey: stakeVKey,
    drep: drep,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

### Delegate Both Stake and Vote

Delegate to both a stake pool and a DRep:

```swift
let tx = try await txBuilder.transactions.stakeAndVoteDelegation(
    stakeVerificationKey: stakeVKey,
    poolOperator: poolOperator,
    drep: drep,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

### Register, Delegate Stake, and Delegate Vote

All three operations in one transaction:

```swift
let tx = try await txBuilder.transactions.stakeAddressRegistrationDelegationAndVoteDelegation(
    stakeVerificationKey: stakeVKey,
    poolOperator: poolOperator,
    drep: drep,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

## DRep Management

### Register as DRep

Register yourself as a Delegated Representative:

```swift
let drepVKey = try DRepVerificationKey.load(from: "path/to/drep.vkey")
let drepSKey = try DRepSigningKey.load(from: "path/to/drep.skey")

// Optional: Add metadata anchor
let anchor = Anchor(
    anchorUrl: try Url("https://example.com/drep-metadata.json"),
    anchorDataHash: AnchorDataHash(payload: metadataHash)
)

let tx = try await txBuilder.transactions.registerDRep(
    drepVerificationKey: drepVKey,
    feePaymentAddress: feePaymentAddress,
    anchor: anchor,  // Optional
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(drepSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

### Update DRep Information

Update your DRep metadata anchor:

```swift
let newAnchor = Anchor(
    anchorUrl: try Url("https://example.com/updated-metadata.json"),
    anchorDataHash: AnchorDataHash(payload: newMetadataHash)
)

let tx = try await txBuilder.transactions.updateDRep(
    drepVerificationKey: drepVKey,
    feePaymentAddress: feePaymentAddress,
    anchor: newAnchor,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(drepSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

### Unregister as DRep

Retire as a DRep and reclaim deposit:

```swift
let tx = try await txBuilder.transactions.unregisterDRep(
    drepVerificationKey: drepVKey,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(drepSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

## Stake Pool Operations

### Register Stake Pool

Register a new stake pool:

```swift
let poolParams = PoolParams(
    poolOperator: poolKeyHash,
    vrfKeyHash: vrfKeyHash,
    pledge: 100_000_000_000,  // 100k ADA
    cost: 340_000_000,         // 340 ADA minimum
    margin: UnitInterval(numerator: 1, denominator: 50),  // 2%
    rewardAccount: rewardAccountHash,
    poolOwners: .list([ownerKeyHash]),
    relays: [
        .singleHostName(SingleHostName(
            port: 3001,
            dnsName: "relay.example.com"
        ))
    ],
    poolMetadata: try PoolMetadata(
        url: try Url("https://example.com/pool-metadata.json"),
        poolMetadataHash: metadataHash
    )
)

let poolSKey = try StakePoolSigningKey.load(from: "path/to/pool.skey")

let tx = try await txBuilder.transactions.poolRegistration(
    poolParams: poolParams,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(poolSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

### Retire Stake Pool

Announce pool retirement (effective after specified epoch):

```swift
let retirementEpoch = 500  // Epoch when pool becomes inactive

let tx = try await txBuilder.transactions.poolRetirement(
    poolKeyHash: poolKeyHash,
    epoch: retirementEpoch,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(poolSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

## Constitutional Committee

### Authorize Committee Hot Key

Authorize a hot key for a constitutional committee cold key:

```swift
let committeeColdVKey = try CommitteeColdVerificationKey.load(from: "path/to/cc-cold.vkey")
let committeeColdSKey = try CommitteeColdSigningKey.load(from: "path/to/cc-cold.skey")
let committeeHotVKey = try CommitteeHotVerificationKey.load(from: "path/to/cc-hot.vkey")

// Optional: Add metadata anchor
let anchor = Anchor(
    anchorUrl: try Url("https://example.com/cc-metadata.json"),
    anchorDataHash: AnchorDataHash(payload: metadataHash)
)

let tx = try await txBuilder.transactions.authCommitteeHot(
    committeeColdVerificationKey: committeeColdVKey,
    committeeHotVerificationKey: committeeHotVKey,
    feePaymentAddress: feePaymentAddress,
    anchor: anchor,  // Optional
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(committeeColdSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

### Resign from Committee

Resign from the constitutional committee:

```swift
let tx = try await txBuilder.transactions.resignCommitteeCold(
    committeeColdVerificationKey: committeeColdVKey,
    feePaymentAddress: feePaymentAddress,
    anchor: anchor,  // Optional
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(committeeColdSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(tx))
```

## Transaction Utilities

### Sign Transaction

Add signatures to an existing unsigned transaction:

```swift
let unsignedTx = // ... existing unsigned transaction

let signedTx = try txBuilder.transactions.sign(
    transaction: unsignedTx,
    signingKeys: [
        .signingKey(paymentSKey),
        .signingKey(stakeSKey)
    ]
)

let txId = try await chainContext.submitTx(tx: .transaction(signedTx))
```

### Assemble Transaction

Merge additional witnesses into an existing transaction:

```swift
let existingTx = // ... existing transaction

let updatedTx = txBuilder.transactions.assemble(
    transaction: existingTx,
    vkeyWitnesses: .list([additionalWitness1, additionalWitness2]),
    nativeScripts: .list([nativeScript]),
    plutusScripts: .list([plutusScript]),
    plutusData: .list([datum1, datum2]),
    redeemers: .list([newRedeemer])  // Note: replaces existing redeemers
)

let txId = try await chainContext.submitTx(tx: .transaction(updatedTx))
```

**Important:** Most witness types are *merged* with existing witnesses, but `redeemers` are *replaced* entirely if provided.

## Common Patterns

### Unsigned Transactions

Get an unsigned transaction for later signing:

```swift
// Pass nil or empty array for signingKeys
let unsignedTx = try await txBuilder.transactions.stakeAddressRegistration(
    stakeVerificationKey: stakeVKey,
    feePaymentAddress: feePaymentAddress,
    signingKeys: nil  // or []
)

// Sign later with the sign helper
let signedTx = try txBuilder.transactions.sign(
    transaction: unsignedTx,
    signingKeys: [.signingKey(paymentSKey), .signingKey(stakeSKey)]
)
```

### Multi-Signature Workflows

Build and partially sign, then collect additional signatures:

```swift
// First signer
let partiallySigned = try await txBuilder.transactions.stakeAddressRegistration(
    stakeVerificationKey: stakeVKey,
    feePaymentAddress: feePaymentAddress,
    signingKeys: [.signingKey(paymentSKey)]
)

// Second signer adds their signature
let fullySigned = txBuilder.transactions.assemble(
    transaction: partiallySigned,
    vkeyWitnesses: .list([secondSignerWitness])
)

let txId = try await chainContext.submitTx(tx: .transaction(fullySigned))
```

### Error Handling

All helpers throw descriptive errors:

```swift
do {
    let tx = try await txBuilder.transactions.stakeDelegation(
        stakeVerificationKey: stakeVKey,
        poolOperator: poolOperator,
        feePaymentAddress: feePaymentAddress,
        signingKeys: signingKeys
    )
    let txId = try await chainContext.submitTx(tx: .transaction(tx))
    
} catch CardanoTxBuilderError.invalidTransaction(let message) {
    print("Invalid transaction: \(message)")
    // e.g., "Staking Address may not be on chain."
    
} catch CardanoTxBuilderError.utxoSelectionFailed(let message) {
    print("UTxO selection failed: \(message)")
    // e.g., insufficient funds at feePaymentAddress
    
} catch {
    print("Unexpected error: \(error)")
}
```

## Summary

| Operation | Helper Method | Required Keys |
|-----------|--------------|---------------|
| Register stake address | `stakeAddressRegistration` | Payment + Stake |
| Deregister stake address | `stakeAddressDeregistration` | Payment + Stake |
| Delegate to pool | `stakeDelegation` | Payment + Stake |
| Register + delegate | `stakeAddressRegistrationAndDelegation` | Payment + Stake |
| Withdraw rewards | `withdrawRewards` | Payment + Stake |
| Delegate vote | `voteDelegation` | Payment + Stake |
| Register + vote delegate | `stakeAddressRegistrationAndVoteDelegation` | Payment + Stake |
| Stake + vote delegate | `stakeAndVoteDelegation` | Payment + Stake |
| All three combined | `stakeAddressRegistrationDelegationAndVoteDelegation` | Payment + Stake |
| Register as DRep | `registerDRep` | Payment + DRep |
| Update DRep | `updateDRep` | Payment + DRep |
| Unregister DRep | `unregisterDRep` | Payment + DRep |
| Register pool | `poolRegistration` | Payment + Pool |
| Retire pool | `poolRetirement` | Payment + Pool |
| Authorize committee hot | `authCommitteeHot` | Payment + Committee Cold |
| Resign from committee | `resignCommitteeCold` | Payment + Committee Cold |
| Sign transaction | `sign` | Any required keys |
| Assemble witnesses | `assemble` | N/A |

All helpers are accessed via `txBuilder.transactions.<method>` and automatically handle UTxO selection, certificate creation, and fee calculation.

## Topics

### Stake Operations
- ``TxBuilder/Transactions/stakeAddressRegistration(stakeVerificationKey:feePaymentAddress:signingKeys:)``
- ``TxBuilder/Transactions/stakeAddressDeregistration(stakeVerificationKey:feePaymentAddress:signingKeys:)``
- ``TxBuilder/Transactions/stakeDelegation(stakeVerificationKey:poolOperator:feePaymentAddress:signingKeys:)``

### Rewards
- ``TxBuilder/Transactions/withdrawRewards(from:to:feePaymentAddress:signingKeys:)``

### Governance
- ``TxBuilder/Transactions/voteDelegation(stakeVerificationKey:drep:feePaymentAddress:signingKeys:)``
- ``TxBuilder/Transactions/registerDRep(drepVerificationKey:feePaymentAddress:anchor:signingKeys:)``

### Pool Operations
- ``TxBuilder/Transactions/poolRegistration(poolParams:feePaymentAddress:signingKeys:)``
- ``TxBuilder/Transactions/poolRetirement(poolKeyHash:epoch:feePaymentAddress:signingKeys:)``

### Utilities
- ``TxBuilder/Transactions/sign(transaction:signingKeys:)``
- ``TxBuilder/Transactions/assemble(transaction:vkeyWitnesses:nativeScripts:plutusScripts:plutusData:redeemers:)``

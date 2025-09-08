# ``SwiftCardanoTxBuilder``

A Swift package for building Cardano transactions with advanced UTxO selection algorithms and comprehensive script support.

## Overview

SwiftCardanoTxBuilder provides a high-level transaction builder that handles UTxO selection, fee calculation, change computation, and transaction validation. It features a fluent Builder API with method chaining, smart UTxO selection algorithms, multi-asset support, and full Plutus script integration.

### Key Features

- 🏗️ **Fluent Builder API**: Easy-to-use method chaining for transaction construction
- 🎯 **Smart UTxO Selection**: Multiple coin selection algorithms (CIP-0002 compliant) 
- 🪙 **Multi-Asset Support**: Native support for Cardano native tokens
- 📜 **Script Integration**: Full support for Plutus and Native scripts
- 💰 **Automatic Fee Calculation**: Smart fee estimation including script execution costs
- 🔄 **Change Handling**: Intelligent change computation with minimum ADA requirements
- ⚡ **Execution Unit Estimation**: Automatic estimation for Plutus script execution
- 🔒 **Collateral Management**: Automatic collateral selection and return handling

### Getting Started

To use SwiftCardanoTxBuilder, you need to initialize a chain context and create a TxBuilder instance:

```swift
import SwiftCardanoTxBuilder
import SwiftCardanoCore
import SwiftCardanoChain

// Initialize BlockFrost chain context
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)

// Create transaction builder
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)
```

## Basic Transaction Building

### Simple ADA Transfer

The most basic transaction transfers ADA from one address to another:

```swift 
// Define addresses
let senderAddress = try Address(from: .string("addr_test1vr..."))
let receiverAddress = try Address(from: .string("addr_test1vq..."))

// Build transaction
let txBody = try await txBuilder
    .addInputAddress(.address(senderAddress))  // Source of funds
    .addOutput(TransactionOutput(
        address: receiverAddress,
        amount: Value(coin: 2_000_000)  // 2 ADA
    ))
    .build(changeAddress: senderAddress)  // Send change back to sender

print("Transaction built with fee: \(txBody.fee)")
```

### Multi-Asset Token Transfer

Transfer native tokens along with ADA:

```swift
// Define token policy and name
let tokenPolicyId = ScriptHash(payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData)
let tokenName = AssetName(from: "MyToken")

// Build multi-asset transaction
let txBody = try await txBuilder
    .addInputAddress(.address(vaultAddress))  // Address containing tokens
    .addOutput(TransactionOutput(
        address: receiverAddress,
        amount: Value(
            coin: 1_500_000,  // 1.5 ADA
            multiAsset: MultiAsset([
                tokenPolicyId: Asset([tokenName: 100])  // 100 tokens
            ])
        )
    ))
    .build(changeAddress: vaultAddress, mergeChange: true)
```

### Input Management

There are two ways to provide transaction inputs:

**Using Input Addresses** (recommended for most cases):
```swift
// Automatically select UTxOs from addresses
txBuilder.addInputAddress(.address(sourceAddress))
txBuilder.addInputAddress(.string("addr_test1vr..."))
```

**Using Specific UTxOs**:
```swift
// Manually specify exact UTxOs to use
let specificUtxo = UTxO(input: txInput, output: txOutput)
txBuilder.addInput(specificUtxo)
```

**Using Potential Inputs**:
```swift
// Provide a pool of UTxOs for the selector to choose from
let availableUtxos = try await chainContext.utxos(address: address)
txBuilder.potentialInputs = availableUtxos
```

## Advanced Transaction Types

### Plutus Script Transactions

For transactions involving smart contracts:

```swift
// Initialize with PlutusData redeemer type
let chainContext = try await BlockFrostChainContext<PlutusData>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<PlutusData, BlockFrostChainContext>(context: chainContext)

// Create script components
let plutusScript = PlutusV2Script(data: Data("script bytes".utf8))
let datum = PlutusData()
let redeemer = Redeemer<PlutusData>(
    data: PlutusData(),
    exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
)

// Add script input
let txBody = try await txBuilder
    .addScriptInput(
        scriptUtxo,
        script: .script(.plutusV2Script(plutusScript)),
        datum: .plutusData(datum),
        redeemer: redeemer
    )
    .addOutput(TransactionOutput(
        address: receiverAddress,
        amount: Value(coin: 5_000_000)
    ))
    .build(changeAddress: receiverAddress)
```

### Token Minting

Mint new native tokens using a minting script:

```swift
// Create minting script and policy
let plutusScript = PlutusV2Script(data: Data("minting script".utf8))
let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))

// Define tokens to mint
txBuilder.mint = try MultiAsset(from: [
    scriptHash.payload.toHex: ["NewToken": 1000]
])

// Add minting script with redeemer
let mintRedeemer = Redeemer<PlutusData>(
    data: PlutusData(),
    exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
)

try txBuilder.addMintingScript(
    .script(.plutusV2Script(plutusScript)),
    redeemer: mintRedeemer
)

// Send minted tokens to recipient
try txBuilder.addOutput(
    TransactionOutput(
        address: receiverAddress,
        amount: Value(
            coin: 2_000_000,
            multiAsset: txBuilder.mint!
        )
    )
)

let txBody = try await txBuilder.build(changeAddress: senderAddress)
```

### Certificates and Governance

Include certificates for stake pool operations or governance actions:

```swift
// Stake pool registration
let poolParams = PoolParams(/* pool parameters */)
let poolRegistration = PoolRegistration(poolParams: poolParams)
txBuilder.certificates = [.poolRegistration(poolRegistration)]
txBuilder.initialStakePoolRegistration = true

// Governance voting
txBuilder.addVote(
    voter: .stakePoolKeyHash(poolKeyHash),
    govActionId: govActionId,
    vote: .yes,
    anchor: voteAnchor
)
```

## Configuration and Customization

### UTxO Selection Algorithms

Configure coin selection strategies:

```swift
// Use custom selector configuration
let txBuilder = TxBuilder(
    context: chainContext,
    utxoSelectors: [
        RandomImproveMultiAsset(),  // Primary selector (CIP-0002)
        LargestFirstSelector()      // Fallback selector
    ]
)
```

### Fee and Execution Configuration

Customize fee calculation and script execution parameters:

```swift
let txBuilder = TxBuilder(
    context: chainContext,
    executionMemoryBuffer: 0.2,     // 20% memory buffer for scripts
    executionStepBuffer: 0.2,       // 20% steps buffer for scripts
    feeBuffer: 100_000,             // Additional 0.1 ADA fee buffer
    ttl: 123456789,                 // Time to live
    collateralReturnThreshold: 5_000_000  // 5 ADA collateral threshold
)
```

### Build Options

Control how the transaction is finalized:

```swift
// Basic build with change address
let txBody = try await txBuilder.build(changeAddress: changeAddress)

// Build with change merging
let txBody = try await txBuilder.build(
    changeAddress: changeAddress, 
    mergeChange: true
)

// Build without specifying change address (no change output)
let txBody = try await txBuilder.build()
```

## Error Handling

The library provides comprehensive error handling for common transaction building issues:

```swift
do {
    let txBody = try await txBuilder.build(changeAddress: senderAddress)
    print("Transaction built successfully")
    
} catch CardanoTxBuilderError.utxoSelectionFailed(let message) {
    print("UTxO selection failed: \(message)")
    // Not enough UTxOs to cover outputs and fees
    
} catch CardanoTxBuilderError.insufficientBalance(let message) {
    print("Insufficient balance: \(message)")
    // Account doesn't have enough funds
    
} catch CardanoTxBuilderError.transactionTooLarge(let message) {
    print("Transaction too large: \(message)")
    // Transaction exceeds protocol limits
    
} catch CardanoTxBuilderError.invalidInput(let message) {
    print("Invalid input: \(message)")
    // Invalid script, address, or datum
}
```

## Redeemer Type Selection

The `TxBuilder` is generic over a redeemer type `T`. Choose the appropriate type based on your transaction requirements:

### Using `Never` for Non-Script Transactions

Use `Never` when your transaction doesn't involve any Plutus scripts:

```swift
// For simple ADA transfers, token transfers without scripts
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// These transactions don't require redeemers:
// - Basic ADA transfers
// - Native token transfers (using existing tokens)
// - Certificate transactions (stake registration, delegation)
// - Transactions using only native scripts
```

### Using `PlutusData` for Plutus Script Transactions

Use `PlutusData` when working with Plutus scripts:

```swift
// For transactions involving Plutus scripts
let chainContext = try await BlockFrostChainContext<PlutusData>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<PlutusData, BlockFrostChainContext>(context: chainContext)

// These transactions require PlutusData redeemers:
// - Spending from Plutus script addresses
// - Minting tokens with Plutus minting policies
// - Certificate transactions with Plutus scripts
// - Withdrawal transactions with Plutus scripts
```

### Using Custom Types for Structured Redeemers

For strongly-typed redeemers, define custom types that conform to `CBORSerializable & Hashable`:

```swift
// Define your custom redeemer type
struct MyRedeemer: CBORSerializable, Hashable {
    let action: String
    let value: Int
    
    // Implement CBORSerializable methods
    func toCBOR() -> CBOR {
        return .array([.string(action), .int(value)])
    }
    
    init(from cbor: CBOR) throws {
        // Deserialize from CBOR
        // Implementation details...
    }
}

// Use with TxBuilder
let chainContext = try await BlockFrostChainContext<MyRedeemer>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<MyRedeemer, BlockFrostChainContext>(context: chainContext)
```

## Transaction Submission

Once you've built a transaction, you need to sign it and submit it to the blockchain:

### Building and Preparing for Submission

```swift
// Build the transaction to sign later
let transactionBody = try await txBuilder.build(changeAddress: senderAddress)

// Create a transaction with the body (witness set will be empty initially)
let unsignedTransaction = Transaction<Never>(
    body: transactionBody,
    witnessSet: txBuilder.buildWitnessSet(),
    isValid: true,
    auxiliaryData: nil
)
```

### Signing the Transaction

Before submitting, you need to sign the transaction with the appropriate private keys:

```swift
// Build the signed transaction
// You need your signing keys

let paymentSigningKey = try PaymentSigningKey.load(from: "path/to/payment.skey")
let signedTransaction = try await txBuilder.buildAndSign(
    signingKeys: [.signingKey(paymentSigningKey)], 
    changeAddress: senderAddress
)

// Or manually sign a pre-built transaction
var vkeyWitnesses = [] as [VerificationKeyWitness]
let vkey: any VerificationKeyProtocol = try paymentSigningKey.toVerificationKey()
let vkeyHash: VerificationKeyHash = try vkey.hash()
let vkeyType: VerificationKeyType = try paymentSigningKey.toVerificationKeyType()
let signature = try paymentSigningKey.sign(
    data: unsignedTransaction.transactionBody.hash()
)
vkeyWitnesses.append(
    VerificationKeyWitness(
        vkey: vkeyType,
        signature: signature
    )
)
unsignedTransaction.witnessSet.vkeyWitnesses = .nonEmptyOrderedSet(
    NonEmptyOrderedSet(vkeyWitnesses)
)
let signedTransaction = unsignedTransaction  // Now signed
```

### Submitting to the Blockchain

Use the chain context to submit your signed transaction:

```swift
do {
    // Submit the signed transaction
    let txId = try await chainContext.submitTx(tx: .transaction(signedTransaction))
    print("Transaction submitted successfully!")
    print("Transaction ID: \(txId)")
    
} catch {
    print("Failed to submit transaction: \(error)")
}
```

### Alternative Submission Methods

The chain context supports multiple submission formats:

```swift
// Submit as transaction object
let txId = try await chainContext.submitTx(tx: .transaction(signedTransaction))

// Submit as raw CBOR bytes
let cborData = signedTransaction.toCBORData()
let txId = try await chainContext.submitTx(tx: .bytes(cborData))

// Submit as hex string
let hexString = cborData.toHex
let txId = try await chainContext.submitTx(tx: .string(hexString))

// Or use the lower-level CBOR method directly
let txId = try await chainContext.submitTxCBOR(cbor: cborData)
```

### Complete Transaction Flow Example

```swift
// 1. Initialize chain context and builder
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

let paymentSigningKey = try PaymentSigningKey.load(from: "path/to/payment.skey")

// 2. Build signed transaction
let txBody = try await txBuilder
    .addInputAddress(.address(senderAddress))
    .addOutput(TransactionOutput(
        address: receiverAddress,
        amount: Value(coin: 2_000_000)
    ))
    .buildAndSign(
        signingKeys: [.signingKey(paymentSigningKey)], 
        changeAddress: senderAddress
    )

// 3. Submit to blockchain
do {
    let txId = try await chainContext.submitTx(tx: .transaction(signedTransaction))
    print("Success! Transaction ID: \(txId)")
    
    // Optional: Monitor transaction confirmation
    // You can query the transaction status using the txId
    
} catch {
    print("Submission failed: \(error)")
}
```

### Error Handling During Submission

```swift
do {
    let txId = try await chainContext.submitTx(tx: .transaction(signedTransaction))
    print("Transaction submitted: \(txId)")
    
} catch ChainContextError.invalidArgument(let message) {
    print("Invalid transaction: \(message)")
    // Transaction is malformed or violates protocol rules
    
} catch ChainContextError.transactionFailed(let message) {
    print("Submission failed: \(message)")
    // Network issues or node rejection
    
} catch {
    print("Unexpected error: \(error)")
}
```

## Topics

### Core Components

- ``TxBuilder``
- ``UTxOSelector``
- ``CardanoTxBuilderError``

### Selection Algorithms

- ``RandomImproveMultiAsset``
- ``LargestFirstSelector``

### Utility Types

- ``CoinSelection``
- ``ExecutionUnitEstimation``

### Testing Support

- ``MockChainContext``

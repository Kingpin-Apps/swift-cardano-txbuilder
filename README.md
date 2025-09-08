# SwiftCardano Transaction Builder

A Swift package for building Cardano transactions with advanced UTxO selection algorithms and comprehensive script support. This library provides a high-level transaction builder that handles UTxO selection, fee calculation, change computation, and transaction validation.

## Features

- 🏗️ **Fluent Builder API**: Easy-to-use method chaining for transaction construction
- 🎯 **Smart UTxO Selection**: Multiple coin selection algorithms (CIP-0002 compliant)
- 🪙 **Multi-Asset Support**: Native support for Cardano native tokens
- 📜 **Script Integration**: Full support for Plutus and Native scripts
- 💰 **Automatic Fee Calculation**: Smart fee estimation including script execution costs
- 🔄 **Change Handling**: Intelligent change computation with minimum ADA requirements
- ⚡ **Execution Unit Estimation**: Automatic estimation for Plutus script execution
- 🔒 **Collateral Management**: Automatic collateral selection and return handling

## Platform Support

- iOS 14.0+
- macOS 14.0+
- watchOS 7.0+
- tvOS 14.0+

## Installation

### Swift Package Manager

Add this to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Kingpin-Apps/swift-cardano-txbuilder.git", from: "0.1.0"),
]
```

**Note:** The examples in this README use `BlockFrostChainContext` for real blockchain interactions. You'll need a BlockFrost API key from [blockfrost.io](https://blockfrost.io) to run the examples.

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/Kingpin-Apps/swift-cardano-txbuilder.git`

## Quick Start

### Basic Transaction

```swift
import SwiftCardanoTxBuilder
import SwiftCardanoCore
import SwiftCardanoChain

// Initialize BlockFrost chain context
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)

// Initialize transaction builder
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// Define addresses
let senderAddress = try Address(from: .string("addr_test1vr..."))
let receiverAddress = try Address(from: .string("addr_test1vq..."))

// Build a simple ADA transfer transaction
let txBody = try await txBuilder
    .addInputAddress(.address(senderAddress))  // Source address
    .addOutput(TransactionOutput(
        address: receiverAddress, // Destination
        amount: Value(coin: 2_000_000)  // 2 ADA
    ))
    .build(changeAddress: senderAddress)

print("Transaction built with fee: \(txBody.fee)")
```

### Multi-Asset Token Transfer

```swift
// Initialize BlockFrost chain context for multi-asset transactions
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// Define token policy and name
let tokenPolicyId = ScriptHash(payload: "1f847bb9ac60e869780037c0510dbd89f745316db7ec4fee81ff1e97".hexStringToData)
let tokenName = AssetName(from: "MyToken")

// Define addresses
let vaultAddress = try Address(from: .string("addr_test1vrs324jltsc0ssuptpa5ngpfk89cps92xa99a2t6vlg6kdqtm5qnv"))
let receiverAddress = try Address(from: .string("addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"))

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
    .build(changeAddress: vaultAddress, mergeChange: true)  // Merge change back to vault
```

### Script Transaction with Plutus

```swift
// Initialize BlockFrost chain context for script transactions
let chainContext = try await BlockFrostChainContext<PlutusData>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<PlutusData, BlockFrostChainContext>(context: chainContext)

// Create Plutus script and addresses
let plutusScript = PlutusV2Script(data: Data("your script bytes here".utf8))
let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))
let scriptAddress = try Address(
    paymentPart: .scriptHash(scriptHash),
    stakingPart: .none,
    network: chainContext.network
)

// Create datum and redeemer
let datum = PlutusData()
let redeemer = Redeemer<PlutusData>(
    data: PlutusData(),
    exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
)

// Create script UTxO
let scriptUtxo = UTxO(
    input: try TransactionInput(from: .list([
        .string("18cbe6cadecd3f89b60e08e68e5e6c7d72d730aaa1ad21431590f7e6643438ef"),
        .int(0)
    ])),
    output: TransactionOutput(
        address: scriptAddress,
        amount: Value(coin: 10_000_000),
        datumHash: try datum.hash()
    )
)

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

### Minting Tokens

```swift
// Initialize BlockFrost chain context for minting
let chainContext = try await BlockFrostChainContext<PlutusData>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<PlutusData, BlockFrostChainContext>(context: chainContext)

// Create minting script
let plutusScript = PlutusV2Script(data: Data("minting script bytes".utf8))
let scriptHash = try plutusScriptHash(script: .plutusV2Script(plutusScript))

// Set up minting MultiAsset
txBuilder.mint = try MultiAsset(from: [
    scriptHash.payload.toHex: ["NewToken": 1000]
])

// Create redeemer for minting
let mintRedeemer = Redeemer<PlutusData>(
    data: PlutusData(),
    exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
)

// Add the minting script
try txBuilder.addMintingScript(
    .script(.plutusV2Script(plutusScript)),
    redeemer: mintRedeemer
)

// Add output with minted tokens
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

## Core Components

### TxBuilder

The main transaction builder class that orchestrates transaction construction:

```swift
public class TxBuilder<T: Codable & Hashable, Context: ChainContext>
```

- **Generic over redeemer type** `T` (use `Never` for non-script transactions, `PlutusData` for Plutus scripts)
- **Generic over chain context** `Context` for network abstraction (e.g., `BlockFrostChainContext`)

**Common initialization patterns:**

```swift
// For simple ADA transactions
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// For Plutus script transactions
let txBuilder = TxBuilder<PlutusData, BlockFrostChainContext>(context: chainContext)

// With custom UTxO selectors
let txBuilder = TxBuilder(
    context: chainContext,
    utxoSelectors: [
        RandomImproveMultiAsset(),  // Primary
        LargestFirstSelector()      // Fallback
    ]
)
```

### UTxO Selection Algorithms

The library includes multiple UTxO selection strategies:

#### RandomImproveMultiAsset (Default)
CIP-0002 compliant random-improve algorithm optimized for multi-asset transactions.

#### LargestFirstSelector (Fallback)
Simple largest-first selection algorithm.

```swift
// Initialize BlockFrost context
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)

// Configure with custom selectors
let txBuilder = TxBuilder(
    context: chainContext,
    utxoSelectors: [
        RandomImproveMultiAsset(),  // Primary
        LargestFirstSelector()      // Fallback
    ]
)
```

### Chain Context Integration

The library works with different chain context implementations. For production use with BlockFrost:

```swift
import SwiftCardanoChain

// Initialize with API key from environment variable
let chainContext = try await BlockFrostChainContext<Never>(
    network: .mainnet,  // or .preview, .preprod
    environmentVariable: "BLOCKFROST_API_KEY"
)

// Or initialize with direct API key
let chainContext = try await BlockFrostChainContext<Never>(
    projectId: "your-blockfrost-project-id",
    network: .mainnet
)

// For script transactions, use the appropriate redeemer type
let scriptChainContext = try await BlockFrostChainContext<PlutusData>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
```

For testing, you can use the provided mock context:

```swift
// Mock context for testing (from test suite)
let mockContext = MockChainContext<Never>()
mockContext._utxos = [/* your test UTxOs */]
let txBuilder = TxBuilder<Never, MockChainContext>(context: mockContext)
```

## Advanced Usage

### Transaction Configuration

```swift
// Initialize with custom configuration
let chainContext = try await BlockFrostChainContext<PlutusData>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)

let txBuilder = TxBuilder(
    context: chainContext,
    executionMemoryBuffer: 0.2,     // 20% memory buffer
    executionStepBuffer: 0.2,       // 20% step buffer
    feeBuffer: 100_000,             // Additional 0.1 ADA fee buffer
    ttl: 123456789,                 // Time to live
    collateralReturnThreshold: 5_000_000  // 5 ADA threshold
)

// Or configure after initialization
txBuilder.ttl = 123456789
txBuilder.feeBuffer = 50_000
txBuilder.executionMemoryBuffer = 0.15
```

### Fee Estimation and Execution Units

The builder automatically handles:
- Transaction size-based fees
- Script execution unit estimation
- Collateral calculation for script transactions
- Minimum UTxO requirements

### Error Handling

```swift
// Initialize chain context and builder
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// Handle errors during transaction building
do {
    let senderAddress = try Address(from: .string("addr_test1vr..."))
    
    let txBody = try await txBuilder
        .addInputAddress(.address(senderAddress))
        .addOutput(TransactionOutput(
            address: try Address(from: .string("addr_test1vq...")),
            amount: Value(coin: 2_000_000)
        ))
        .build(changeAddress: senderAddress)
        
    print("Transaction built successfully with fee: \(txBody.fee)")
    
} catch CardanoTxBuilderError.utxoSelectionFailed(let message) {
    print("UTxO selection failed: \(message)")
} catch CardanoTxBuilderError.insufficientBalance(let message) {
    print("Insufficient balance: \(message)")
} catch CardanoTxBuilderError.transactionTooLarge(let message) {
    print("Transaction too large: \(message)")
} catch CardanoTxBuilderError.invalidInput(let message) {
    print("Invalid input: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Common Error Types

- `utxoSelectionFailed`: Not enough UTxOs to cover outputs and fees
- `insufficientBalance`: Insufficient funds for the transaction
- `transactionTooLarge`: Transaction exceeds protocol limits
- `invalidInput`: Invalid script, address, or datum validation

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

## Examples

### Stake Pool Registration

```swift
// Initialize chain context
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// Define pool parameters
let poolParams = PoolParams(
    poolOperator: PoolKeyHash(payload: Data(repeating: 0x31, count: POOL_KEY_HASH_SIZE)),
    vrfKeyHash: VrfKeyHash(payload: Data(repeating: 0x31, count: VRF_KEY_HASH_SIZE)),
    pledge: 100_000_000_000,  // 100k ADA
    cost: 340_000_000,        // 340 ADA
    margin: UnitInterval(numerator: 1, denominator: 50), // 2%
    rewardAccount: RewardAccountHash(payload: Data(repeating: 0x31, count: REWARD_ACCOUNT_HASH_SIZE)),
    poolOwners: .list([
        VerificationKeyHash(payload: Data(repeating: 0x31, count: VERIFICATION_KEY_HASH_SIZE))
    ]),
    relays: [
        .singleHostAddr(SingleHostAddr(
            port: 3001,
            ipv4: IPv4Address("192.168.0.1")!,
            ipv6: IPv6Address("::1")!
        )),
        .singleHostName(SingleHostName(
            port: 3001,
            dnsName: "relay1.example.com"
        ))
    ],
    poolMetadata: try PoolMetadata(
        url: try Url("https://meta1.example.com"),
        poolMetadataHash: PoolMetadataHash(payload: Data(repeating: 0x31, count: POOL_METADATA_HASH_SIZE))
    )
)

// Create pool registration certificate
let poolRegistration = PoolRegistration(poolParams: poolParams)

// Add input UTxO with sufficient funds
let ownerAddress = try Address(from: .string("addr_test1vr..."))
let poolUtxo = UTxO(
    input: try TransactionInput(from: .list([
        .bytes(Data(repeating: 0x32, count: 32)),
        .int(2)
    ])),
    output: TransactionOutput(
        address: ownerAddress,
        amount: Value(coin: 505_000_000)  // 505 ADA
    )
)

// Configure transaction
txBuilder.addInput(poolUtxo)
txBuilder.initialStakePoolRegistration = true
txBuilder.certificates = [.poolRegistration(poolRegistration)]

let txBody = try await txBuilder.build(changeAddress: ownerAddress)
```

### Governance Voting

```swift
// Initialize chain context
let chainContext = try await BlockFrostChainContext<Never>(
    network: .preview,
    environmentVariable: "BLOCKFROST_API_KEY"
)
let txBuilder = TxBuilder<Never, BlockFrostChainContext>(context: chainContext)

// Define governance action and voter
let poolKeyHash = PoolKeyHash(payload: Data(repeating: 0x31, count: POOL_KEY_HASH_SIZE))
let govActionId = GovActionID(
    transactionId: try TransactionId(from: .string("41cb004bec7051621b19b46aea28f0657a586a05ce2013152ea9b9f1a5614cc7")),
    govActionIndex: 0
)

// Optional vote anchor for metadata
let voteAnchor = Anchor(
    anchorUrl: try Url("https://vote-metadata.example.com"),
    anchorDataHash: AnchorDataHash(payload: Data(repeating: 0x42, count: 32))
)

// Add vote to transaction
txBuilder.addVote(
    voter: .stakePoolKeyHash(poolKeyHash),
    govActionId: govActionId,
    vote: .yes,
    anchor: voteAnchor
)

// Add funding input and build
let voterAddress = try Address(from: .string("addr_test1vr..."))
txBuilder.addInputAddress(.address(voterAddress))

let txBody = try await txBuilder.build(changeAddress: voterAddress)
```

## Dependencies

- [SwiftCardanoCore](https://github.com/Kingpin-Apps/swift-cardano-core): Core Cardano types and CBOR encoding
- [SwiftCardanoChain](https://github.com/Kingpin-Apps/swift-cardano-chain): Chain context and network protocol abstractions
- [SwiftNcal](https://github.com/Kingpin-Apps/swift-ncal): Cryptographic functions

## Architecture

### Transaction Building Pipeline

1. **Input Collection**: Gather UTxOs from addresses or explicit inputs
2. **UTxO Selection**: Apply selection algorithms to meet output requirements  
3. **Script Handling**: Process Plutus/Native scripts with redeemers and datums
4. **Fee Estimation**: Calculate transaction fees including script execution costs
5. **Change Calculation**: Compute change outputs with minimum ADA requirements
6. **Validation**: Ensure transaction meets protocol constraints

### Design Patterns

- **Builder Pattern**: Fluent API with method chaining
- **Strategy Pattern**: Pluggable UTxO selection algorithms
- **Generic Context**: Abstraction for different network environments
- **Protocol-Oriented**: Extensible design with clear interfaces

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Development Setup

```bash
git clone https://github.com/Kingpin-Apps/swift-cardano-txbuilder.git
cd swift-cardano-txbuilder
swift package resolve
swift build
swift test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📖 [Documentation](https://github.com/Kingpin-Apps/swift-cardano-txbuilder/wiki)
- 🐛 [Issue Tracker](https://github.com/Kingpin-Apps/swift-cardano-txbuilder/issues)
- 💬 [Discussions](https://github.com/Kingpin-Apps/swift-cardano-txbuilder/discussions)

---

Built with ❤️ for the Cardano ecosystem

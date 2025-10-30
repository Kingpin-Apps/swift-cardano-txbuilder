import Foundation
import Logging
import SwiftCardanoChain
import SwiftCardanoCore

/// A class builder that makes it easy to build a transaction.
public class TxBuilder: Loggable {
    // MARK: - Loggable Conformance
    public var logger: Logging.Logger

    // MARK: - Constants
    /// A fake verification key for fee calculation purpose only
    private static var FAKE_VKEY: any VerificationKeyProtocol {
        try! VerificationKey(
            payload: Data(
                hex: "5797dc2cc919dfec0bb849551ebdf30d96e5cbe0f33f734a87fe826db30f7ef9"
            )
        )
    }

    // Ed25519 signature of a 32-bytes message (TX hash) will have length of 64
    private static var FAKE_TX_SIGNATURE: Data {
        Data(
            hex:
                "577ccb5b487b64e396b0976c6f71558e52e44ad254db7d06dfb79843e5441a5d763dd42adcf5e8805d70373722ebbce62a58e3f30dd4560b9a898b8ceeab6a03"
        )
    }

    // MARK: - Properties

    /// The chain context for this transaction builder
    public let context: any ChainContext

    /// UTxO selectors used for coin selection
    public var utxoSelectors: [UTxOSelector] = [RandomImproveMultiAsset(), LargestFirstSelector()]

    /// Additional amount of execution memory (in ratio) that will be on top of estimation
    public var executionMemoryBuffer: Double = 0.2

    /// Additional amount of execution step (in ratio) that will be added on top of estimation
    public var executionStepBuffer: Double = 0.2

    /// Additional amount of fee (in lovelace) that will be added on top of estimation
    public var feeBuffer: Int?

    /// Time-to-live for the transaction
    public var ttl: Int?

    /// Validity start time for the transaction
    public var validityStart: Int?

    /// Auxiliary data for the transaction
    public var auxiliaryData: AuxiliaryData?

    /// Native scripts used in the transaction
    public var nativeScripts: [NativeScript]?

    /// Assets to mint in the transaction
    public var mint: MultiAsset?

    /// Required signers for the transaction
    public var requiredSigners: [VerificationKeyHash]?

    /// Collateral inputs for the transaction
    public var collaterals: [UTxO] = []

    /// Certificates to include in the transaction
    public var certificates: [Certificate]?

    /// Withdrawals to include in the transaction
    public var withdrawals: Withdrawals?

    /// Reference inputs for the transaction
    public private(set) var referenceInputs: Set<UTxOOrTransactionInput> = []

    /// Override for witness count
    public var witnessOverride: Int?

    /// Whether this is an initial stake pool registration
    public var initialStakePoolRegistration: Bool = false

    /// Whether to serialize redeemers as a map or a list. Default is true.
    public var useRedeemerMap: Bool = true

    /// Voting procedures for the transaction
    public private(set) var votingProcedures: VotingProcedures?

    /// Proposal procedures for the transaction
    public private(
        set
    ) var proposalProcedures: NonEmptyOrderedSet<ProposalProcedure>?

    /// Current treasury value
    public private(set) var currentTreasuryValue: Int?

    /// Donation amount
    public private(set) var donation: Int?
    
    /// Inputs to scripts mapping
    public var inputsToScripts: [UTxO: ScriptType] {
        get { _inputsToScripts }
        set { _inputsToScripts = newValue }
    }
    
    /// Inputs to scripts mapping
    public var redeemerListOverride: [Redeemer] {
        get { _redeemers }
        set { _redeemers = newValue }
    }

    // MARK: - Private Properties

    private var _inputs: [UTxO] = []
    private var _potentialInputs: [UTxO] = []
    private var _excludedInputs: [UTxO] = []
    private var _inputAddresses: [AddressOrString] = []
    private var _outputs: [TransactionOutput] = []
    private var _fee: Int = 0
    private var _datums: [DatumHash: Datum] = [:]
    private var _collateralReturn: TransactionOutput?
    private var _totalCollateral: Int?
    private var _redeemers: [Redeemer] = []
    private var _inputsToRedeemers: [UTxO: Redeemer] = [:]
    private var _mintingScriptToRedeemers: [(ScriptType, Redeemer?)] = []
    private var _withdrawalScriptToRedeemers: [(ScriptType, Redeemer?)] = []
    private var _certificateScriptToRedeemers: [(ScriptType, Redeemer?)] = []
    private var _inputsToScripts: [UTxO: ScriptType] = [:]
    private var _referenceScripts: [ScriptType] = []
    private var _shouldEstimateExecutionUnits: Bool?

    /// The minimum amount of lovelace above which the remaining collateral  (total_collateral_amount - actually_used_amount)  will be returned
    public var collateralReturnThreshold: Int = 1_000_000

    // MARK: - Initialization

    /// Initialize a new transaction builder
    /// - Parameter context: The chain context to use
    public init(context: any ChainContext,
                utxoSelectors: [UTxOSelector] = [RandomImproveMultiAsset(), LargestFirstSelector()],
                executionMemoryBuffer: Double = 0.2,
                executionStepBuffer: Double = 0.2,
                feeBuffer: Int? = nil,
                ttl: Int? = nil,
                validityStart: Int? = nil,
                auxiliaryData: AuxiliaryData? = nil,
                nativeScripts: [NativeScript]? = nil,
                mint: MultiAsset? = nil,
                requiredSigners: [VerificationKeyHash]? = nil,
                collaterals: [UTxO] = [],
                certificates: [Certificate]? = nil,
                withdrawals: Withdrawals? = nil,
                collateralReturnThreshold: Int? = nil,
    ) {
        self.context = context
        self.utxoSelectors = utxoSelectors
        self.executionMemoryBuffer = executionMemoryBuffer
        self.executionStepBuffer = executionStepBuffer
        self.feeBuffer = feeBuffer
        self.ttl = ttl
        self.validityStart = validityStart
        self.auxiliaryData = auxiliaryData
        self.nativeScripts = nativeScripts
        self.mint = mint
        self.requiredSigners = requiredSigners
        self.collaterals = collaterals
        self.collateralReturnThreshold = collateralReturnThreshold ?? 1_000_000
        self.certificates = certificates
        self.withdrawals = withdrawals
        
        self.logger = Logger(label: "com.swift-cardano-txbuilder")
        setupLogging()
    }

    // MARK: - Public Methods

    /// Add a specific UTxO to transaction's inputs.
    /// - Parameter utxo: UTxO to be added
    /// - Returns: Current transaction builder
    @discardableResult
    public func addInput(_ utxo: UTxO) -> TxBuilder {
        _inputs.append(utxo)
        return self
    }

    /// Add a script UTxO to transaction's inputs.
    /// - Parameters:
    ///   - utxo: Script UTxO to be added
    ///   - script: A plutus script. If not provided, the script will be inferred from the input UTxO
    ///   - datum: A plutus datum to unlock the UTxO
    ///   - redeemer: A plutus redeemer to unlock the UTxO
    /// - Returns: Current transaction builder
    @discardableResult
    public func addScriptInput(
        _ utxo: UTxO,
        script: ScriptOrUTxO? = nil,
        datum: Datum? = nil,
        redeemer: Redeemer? = nil
    ) async throws -> TxBuilder {
        guard
            case let addressType = utxo.output.address.addressType,
            addressType == .scriptKey || addressType == .scriptScript || addressType == .scriptPointer || addressType == .scriptNone
        else {
            throw CardanoTxBuilderError.invalidInput(
                "Expect the output address of utxo to be script type, but got \(String(describing: utxo.output.address.addressType)) instead."
            )
        }

        if let _datumHash = utxo.output.datumHash,
            let datum = datum,
            try datumHash(datum: datum) != _datumHash
        {
            throw CardanoTxBuilderError.invalidInput(
                "Datum hash in transaction output is \(String(describing: datumHash)), but actual datum hash is \(try datumHash(datum: datum))."
            )
        }

        if datum != nil,
            utxo.output.datumHash == nil,
            utxo.output.datumOption != nil
        {
            throw CardanoTxBuilderError.invalidInput(
                "Inline Datum found in transaction output \(utxo.input), so attaching a Datum manually is not allowed"
            )
        }

        if let datum = datum {
            _datums[try datumHash(datum: datum)] = datum
        }

        if var redeemer = redeemer {
            if let tag = redeemer.tag,
                tag != .spend
            {
                throw CardanoTxBuilderError.invalidInput(
                    "Expected redeemer tag \(RedeemerTag.spend) but got \(tag)")
            }
            redeemer.tag = .spend
            try consolidateRedeemer(&redeemer)
            _inputsToRedeemers[utxo] = redeemer
        }

        guard case let .scriptHash(inputScriptHash) = utxo.output.address.paymentPart else {
            throw CardanoTxBuilderError.invalidInput(
                "Expected script hash in payment part of input address")
        }
        //        let inputScriptHash = utxo.output.address.paymentPart

        // Collect potential scripts to fulfill the input
        var candidateScripts: [(script: ScriptType, utxo: UTxO?)] = []

        if let outputScript = utxo.output.script {
            candidateScripts.append((outputScript, utxo))
        } else if script == nil {
            // First, check potential inputs for scripts
            for i in potentialInputs {
                if let script = i.output.script {
                    candidateScripts.append((script, i))
                }
            }
            
            // Then, check chain context UTxOs for scripts
            let utxos = try await context.utxos(address: utxo.output.address)
            for i in utxos {
                if let script = i.output.script {
                    candidateScripts.append((script, i))
                }
            }
        } else if case let .utxo(utxo) = script {
            guard let outputScript = utxo.output.script else {
                throw CardanoTxBuilderError.invalidInput(
                    "Expected script in reference UTxO \(utxo) but found none."
                )
            }
            candidateScripts.append((outputScript, utxo))
        } else if case let .script(scriptType) = script {
            candidateScripts.append((scriptType, nil))
        }

        var foundValidScript = false
        for (candidateScript, candidateUtxo) in candidateScripts {
            if try scriptHash(script: candidateScript) != inputScriptHash {
                continue
            }

            foundValidScript = true
            _inputsToScripts[utxo] = candidateScript

            if let candidateUtxo = candidateUtxo,
                candidateUtxo != utxo
            {
                referenceInputs.insert(.utxo(candidateUtxo))
                _referenceScripts.append(candidateScript)
            }
            break
        }

        if !foundValidScript {
            throw CardanoTxBuilderError.invalidInput(
                "Cannot find valid script for input UTxO: \(utxo.input). "
                    + "Supplied scripts do not match payment part of input address."
            )
        }

        _inputs.append(utxo)
        return self
    }

    /// Add a minting script along with its redeemer to this transaction.
    /// - Parameters:
    ///   - script: A plutus script or UTxO containing a script
    ///   - redeemer: A plutus redeemer for minting
    /// - Returns: Current transaction builder
    @discardableResult
    public func addMintingScript(
        _ script: ScriptOrUTxO,
        redeemer: Redeemer? = nil
    ) throws -> TxBuilder {
        var modifiedRedeemer = redeemer
        if var redeemer = redeemer {
            if let tag = redeemer.tag,
                tag != .mint
            {
                throw CardanoTxBuilderError.invalidInput(
                    "Expected redeemer tag \(RedeemerTag.mint) but got \(tag)")
            }
            redeemer.tag = .mint
            try consolidateRedeemer(&redeemer)
            modifiedRedeemer = redeemer
        }

        if case let .utxo(utxo) = script {
            guard let outputScript = utxo.output.script else {
                throw CardanoTxBuilderError.invalidInput("Expected script in UTxO but found none")
            }
            _mintingScriptToRedeemers.append((outputScript, modifiedRedeemer))
            referenceInputs.insert(.utxo(utxo))
            _referenceScripts.append(outputScript)
        } else if case let .script(scriptType) = script {
            _mintingScriptToRedeemers.append((scriptType, modifiedRedeemer))
        }

        return self
    }

    /// Add a withdrawal script along with its redeemer to this transaction.
    /// - Parameters:
    ///   - script: A plutus script or UTxO containing a script
    ///   - redeemer: A plutus redeemer for withdrawal
    /// - Returns: Current transaction builder
    @discardableResult
    public func addWithdrawalScript(
        _ script: ScriptOrUTxO,
        redeemer: Redeemer? = nil
    ) throws -> TxBuilder {
        var modifiedRedeemer = redeemer
        if var redeemer = redeemer {
            if let tag = redeemer.tag,
                tag != .reward
            {
                throw CardanoTxBuilderError.invalidInput(
                    "Expected redeemer tag \(RedeemerTag.reward) but got \(tag)")
            }
            redeemer.tag = .reward
            try consolidateRedeemer(&redeemer)
            modifiedRedeemer = redeemer
        }

        if case let .utxo(utxo) = script {
            guard let outputScript = utxo.output.script else {
                throw CardanoTxBuilderError.invalidInput("Expected script in UTxO but found none")
            }
            _withdrawalScriptToRedeemers.append((outputScript, modifiedRedeemer))
            referenceInputs.insert(.utxo(utxo))
            _referenceScripts.append(outputScript)
        } else if case let .script(scriptType) = script {
            _withdrawalScriptToRedeemers.append((scriptType, modifiedRedeemer))
        }

        return self
    }

    /// Add a certificate script along with its redeemer to this transaction.
    /// WARNING: The order of operations matters.
    /// The index of the redeemer will be set to the index of the last certificate added.
    /// - Parameters:
    ///   - script: A plutus script or UTxO containing a script
    ///   - redeemer: A plutus redeemer for the certificate
    /// - Returns: Current transaction builder
    @discardableResult
    public func addCertificateScript(
        _ script: ScriptOrUTxO,
        redeemer: Redeemer? = nil
    ) throws -> TxBuilder {
        var modifiedRedeemer = redeemer
        if var redeemer = redeemer {
            if let tag = redeemer.tag,
                tag != .cert
            {
                throw CardanoTxBuilderError.invalidInput(
                    "Expected redeemer tag \(RedeemerTag.cert) but got \(tag)")
            }

            guard let certificates = certificates,
                !certificates.isEmpty
            else {
                throw CardanoTxBuilderError.invalidState(
                    "No certificates found. Redeemer index needs to be set to the index of the corresponding certificate."
                )
            }

            redeemer.index = certificates.count - 1
            redeemer.tag = .cert
            try consolidateRedeemer(&redeemer)
            modifiedRedeemer = redeemer
        }

        if case let .utxo(utxo) = script {
            guard let outputScript = utxo.output.script else {
                throw CardanoTxBuilderError.invalidInput("Expected script in UTxO but found none")
            }
            _certificateScriptToRedeemers.append((outputScript, modifiedRedeemer))
            referenceInputs.insert(.utxo(utxo))
            _referenceScripts.append(outputScript)
        } else if case let .script(scriptType) = script {
            _certificateScriptToRedeemers.append((scriptType, modifiedRedeemer))
        }

        return self
    }

    /// Add an address to transaction's input address.
    /// Unlike `addInput`, which deterministically adds a UTxO to the transaction's inputs,
    /// `addInputAddress` will not immediately select any UTxO when called. Instead, it will
    /// delegate UTxO selection to UTxOSelectors of the builder when `build` is called.
    /// - Parameter address: Address to be added
    /// - Returns: Current transaction builder
    @discardableResult
    public func addInputAddress(_ address: AddressOrString) -> TxBuilder {
        _inputAddresses.append(address)
        return self
    }

    /// Add a transaction output.
    /// - Parameters:
    ///   - output: The transaction output to be added
    ///   - datum: Attach a datum hash to this transaction output
    ///   - addDatumToWitness: Optionally add the actual datum to transaction witness set
    /// - Returns: Current transaction builder
    @discardableResult
    public func addOutput(
        _ output: TransactionOutput,
        datum: Datum? = nil,
        addDatumToWitness: Bool = false
    ) throws -> TxBuilder {
        var output = output
        if let datum = datum {
            output.datumHash = try datumHash(datum: datum)
        }

        _outputs.append(output)

        if let datum = datum,
            addDatumToWitness
        {
            _datums[try datumHash(datum: datum)] = datum
        }
        return self
    }

    /// Build the transaction witness set.
    public func buildWitnessSet(removeDupScript: Bool = false) throws -> TransactionWitnessSet {
        var nativeScriptElements: [NativeScript] = []
        var plutusV1ScriptElements: [PlutusV1Script] = []
        var plutusV2ScriptElements: [PlutusV2Script] = []
        var plutusV3ScriptElements: [PlutusV3Script] = []

        let inputScripts: OrderedSet<ScriptHash>
        if removeDupScript {
            inputScripts = try OrderedSet(
                Set(
                    inputs.compactMap { input in
                        if let script = input.output.script {
                            return try? scriptHash(script: script)
                        }
                        return nil
                    }))
        } else {
            inputScripts = try OrderedSet<ScriptHash>([])
        }

        for script in scripts {
            let scriptHash = try scriptHash(script: script)
            if !inputScripts.contains(scriptHash) {
                switch script {
                case .nativeScript(let nativeScript):
                    nativeScriptElements.append(nativeScript)
                case .plutusV1Script(let plutusScript):
                    plutusV1ScriptElements.append(plutusScript)
                case .plutusV2Script(let plutusScript):
                    plutusV2ScriptElements.append(plutusScript)
                case .plutusV3Script(let plutusScript):
                    plutusV3ScriptElements.append(plutusScript)
                }
            }
        }

        return TransactionWitnessSet(
            vkeyWitnesses: nil,
            nativeScripts: nativeScriptElements.isEmpty
                ? nil
            : .nonEmptyOrderedSet(NonEmptyOrderedSet<NativeScript>(
                    nativeScriptElements
                )),
            bootstrapWitness: nil,
            plutusV1Script: plutusV1ScriptElements.isEmpty
                ? nil
            : .nonEmptyOrderedSet(NonEmptyOrderedSet<PlutusV1Script>(
                    plutusV1ScriptElements
                )),
            plutusV2Script: plutusV2ScriptElements.isEmpty
                ? nil
                : .nonEmptyOrderedSet(NonEmptyOrderedSet<PlutusV2Script>(
                    plutusV2ScriptElements
                )),
            plutusData: datums.isEmpty
                ? nil
                : .nonEmptyOrderedSet(NonEmptyOrderedSet<PlutusData>(
                    try datums.values.map { try $0.toPlutusData() }
                )),
            redeemers: try _redeemerList.isEmpty ? nil : redeemers(),
            plutusV3Script: plutusV3ScriptElements.isEmpty
                ? nil : .nonEmptyOrderedSet(NonEmptyOrderedSet<PlutusV3Script>(plutusV3ScriptElements))
        )
    }
    
    public func copy() -> TxBuilder {
        let copy = TxBuilder.init(
            context: self.context,
            utxoSelectors: self.utxoSelectors,
            executionMemoryBuffer: self.executionMemoryBuffer,
            executionStepBuffer: self.executionStepBuffer,
            feeBuffer: self.feeBuffer,
            ttl: self.ttl,
            validityStart: self.validityStart,
            auxiliaryData: self.auxiliaryData,
            nativeScripts: self.nativeScripts,
            mint: self.mint,
            requiredSigners: self.requiredSigners,
            collaterals: self.collaterals,
            certificates: self.certificates,
            withdrawals: self.withdrawals,
            collateralReturnThreshold: self.collateralReturnThreshold,
        )
        
        // Copy private state
        copy._inputs = self._inputs
        copy._potentialInputs = self._potentialInputs
        copy._excludedInputs = self._excludedInputs
        copy._inputAddresses = self._inputAddresses
        copy._outputs = self._outputs
        copy._fee = self._fee
        copy._datums = self._datums
        copy._collateralReturn = self._collateralReturn
        copy._totalCollateral = self._totalCollateral
        copy._inputsToRedeemers = self._inputsToRedeemers
        copy._mintingScriptToRedeemers = self._mintingScriptToRedeemers
        copy._withdrawalScriptToRedeemers = self._withdrawalScriptToRedeemers
        copy._certificateScriptToRedeemers = self._certificateScriptToRedeemers
        copy._inputsToScripts = self._inputsToScripts
        copy._referenceScripts = self._referenceScripts
        copy._shouldEstimateExecutionUnits = self._shouldEstimateExecutionUnits
        copy.referenceInputs = self.referenceInputs
        copy.votingProcedures = self.votingProcedures
        copy.proposalProcedures = self.proposalProcedures
        copy.currentTreasuryValue = self.currentTreasuryValue
        copy.donation = self.donation
        copy.witnessOverride = self.witnessOverride
        copy.initialStakePoolRegistration = self.initialStakePoolRegistration
        copy.useRedeemerMap = self.useRedeemerMap
        
        return copy
    }

    // MARK: - Public Properties

    /// The transaction inputs
    public var inputs: [UTxO] {
        get { _inputs }
        set { _inputs = newValue }
    }

    /// The potential inputs that may be used
    public var potentialInputs: [UTxO] {
        get { _potentialInputs }
        set { _potentialInputs = newValue }
    }

    /// The excluded inputs that should not be used
    public var excludedInputs: [UTxO] {
        get { _excludedInputs }
        set { _excludedInputs = newValue }
    }

    /// The input addresses to select UTxOs from
    public var inputAddresses: [AddressOrString] {
        get { _inputAddresses }
        set { _inputAddresses = newValue }
    }

    /// The transaction outputs
    public var outputs: [TransactionOutput] {
        get { _outputs }
        set { _outputs = newValue }
    }

    /// The transaction fee
    public var fee: Int {
        get { _fee }
        set { _fee = newValue }
    }

    /// All scripts used in the transaction
    public var allScripts: [ScriptType] {
        var scripts: [ScriptHash: ScriptType] = [:]

        if let nativeScripts = nativeScripts {
            for script in nativeScripts {
                let _scriptHash = try! scriptHash(script: .nativeScript(script))
                scripts[_scriptHash] = .nativeScript(script)
            }
        }

        for script in _inputsToScripts.values {
            let _scriptHash = try! scriptHash(script: script)
            scripts[_scriptHash] = script
        }

        for (script, _) in _mintingScriptToRedeemers {
            let _scriptHash = try! scriptHash(script: script)
            scripts[_scriptHash] = script
        }

        for (script, _) in _withdrawalScriptToRedeemers {
            let _scriptHash = try! scriptHash(script: script)
            scripts[_scriptHash] = script
        }

        for (script, _) in _certificateScriptToRedeemers {
            let _scriptHash = try! scriptHash(script: script)
            scripts[_scriptHash] = script
        }

        return Array(scripts.values)
    }

    /// Scripts that need to be included in the witness set
    public var scripts: [ScriptType] {
        var scripts: [ScriptHash: ScriptType] = [:]

        for script in allScripts {
            let _scriptHash = try! scriptHash(script: script)
            scripts[_scriptHash] = script
        }

        for script in _referenceScripts {
            let _scriptHash = try! scriptHash(script: script)
            scripts.removeValue(forKey: _scriptHash)
        }

        return Array(scripts.values)
    }

    /// The datums used in the transaction
    public var datums: [DatumHash: Datum] {
        _datums
    }

    /// The redeemers used in the transaction
    private var _redeemerList: [Redeemer] {
        if self.redeemerListOverride.count > 0 {
            return self.redeemerListOverride
        }
        
        var redeemers: [Redeemer] = []

        redeemers += _inputsToRedeemers.values.map { $0 }
        redeemers += _mintingScriptToRedeemers.compactMap { $0.1 }
        redeemers += _withdrawalScriptToRedeemers.compactMap { $0.1 }
        redeemers += _certificateScriptToRedeemers.compactMap { $0.1 }

        redeemers.sort { $0.index < $1.index }
        return redeemers
        
    }

    /// Get the redeemers for the transaction
    /// - Throws: CardanoTxBuilderError if redeemer is in invalid state
    /// - Returns: Redeemers in either map or list format
    public func redeemers() throws -> Redeemers {
        let redeemerList = _redeemerList

        // We have to serialize redeemers as a map if there are no redeemers
        if useRedeemerMap || redeemerList.isEmpty {
            var redeemers = RedeemerMap()

            for redeemer in redeemerList {
                guard let tag = redeemer.tag else {
                    throw CardanoTxBuilderError.invalidState("Redeemer tag is not set: \(redeemer)")
                }

                guard let exUnits = redeemer.exUnits else {
                    throw CardanoTxBuilderError.invalidState(
                        "Execution units are not set: \(redeemer)")
                }

                let key = RedeemerKey(tag: tag, index: redeemer.index)
                let value = RedeemerValue(data: redeemer.data, exUnits: exUnits)
                redeemers[key] = value
            }

            return .map(redeemers)
        } else {
            return .list(redeemerList)
        }
    }

    // MARK: - Governance Methods

    /// Add a vote to the transaction.
    /// - Parameters:
    ///   - voter: The voter casting the vote
    ///   - govActionId: The ID of the governance action being voted on
    ///   - vote: The vote being cast (YES/NO/ABSTAIN)
    ///   - anchor: Optional metadata about the vote
    /// - Returns: Current transaction builder
    @discardableResult
    public func addVote(
        voter: Voter,
        govActionId: GovActionID,
        vote: Vote,
        anchor: Anchor? = nil
    ) -> TxBuilder {
        if votingProcedures == nil {
            votingProcedures = VotingProcedures([:])
        }

        // Initialize the inner map if this is the first vote for this voter
        if votingProcedures!.voters.contains(where: { $0 == voter }) {
            votingProcedures![voter] = [:]
        }

        // Add the voting procedure for this specific governance action
        votingProcedures![voter]![govActionId] = VotingProcedure(
            vote: vote, anchor: anchor)

        return self
    }

    /// Add a governance proposal to the transaction.
    /// - Parameters:
    ///   - deposit: The deposit amount required for the proposal
    ///   - rewardAccount: The reward account for the proposal
    ///   - govAction: The governance action being proposed
    ///   - anchor: Metadata about the proposal
    /// - Returns: Current transaction builder
    @discardableResult
    public func addProposal(
        deposit: Int,
        rewardAccount: Data,
        govAction: GovAction,
        anchor: Anchor
    ) -> TxBuilder {
        let procedure = ProposalProcedure(
            deposit: Coin(deposit),
            rewardAccount: rewardAccount,
            govAction: govAction,
            anchor: anchor
        )

        if proposalProcedures == nil {
            proposalProcedures = NonEmptyOrderedSet([procedure])
        } else {
            proposalProcedures?.elements.insert(procedure)
        }

        return self
    }

    /// Add a donation to the treasury.
    /// - Parameter amount: The amount to donate (must be positive)
    /// - Returns: Current transaction builder
    /// - Throws: CardanoTxBuilderError if amount is not positive
    @discardableResult
    public func addTreasuryDonation(_ amount: Int) throws -> TxBuilder {
        guard amount > 0 else {
            throw CardanoTxBuilderError.invalidInput("Treasury donation amount must be positive")
        }
        donation = amount
        return self
    }

    // MARK: - Build Methods

    /// Build a transaction body from all constraints set through the builder.
    /// - Parameters:
    ///   - changeAddress: Address to which changes will be returned
    ///   - mergeChange: If true and the change address matches a transaction output, merge the change into that output
    ///   - collateralChangeAddress: Address to which collateral changes will be returned
    ///   - autoValidityStartOffset: Automatically set validity start interval (default -1000)
    ///   - autoTtlOffset: Automatically set validity end interval (default 10_000)
    ///   - autoRequiredSigners: Automatically add input pubkeyhashes to required signers
    /// - Returns: A transaction body
    /// - Throws: CardanoTxBuilderError if the transaction cannot be built
    public func build(
        changeAddress: Address? = nil,
        mergeChange: Bool = false,
        collateralChangeAddress: Address? = nil,
        autoValidityStartOffset: Int? = nil,
        autoTtlOffset: Int? = nil,
        autoRequiredSigners: Bool? = nil
    ) async throws -> TransactionBody {
        do {
            try ensureNoInputExclusionConflict()

            // Only automatically set the validity interval and required signers if scripts are involved
            let isSmart = !allScripts.isEmpty

            // Automatically set the validity range to a tight value around transaction creation
            if (isSmart || autoValidityStartOffset != nil) && validityStart == nil {
                let lastSlot = try await context.lastBlockSlot()
                // If None is provided, the default value is -1000
                let offset = autoValidityStartOffset ?? -1000
                validityStart = max(0, lastSlot + offset)
            }

            if (isSmart || autoTtlOffset != nil) && ttl == nil {
                let lastSlot = try await context.lastBlockSlot()
                // If None is provided, the default value is 10_000
                let offset = autoTtlOffset ?? 10_000
                ttl = max(0, lastSlot + offset)
            }

            var selectedUtxos: [UTxO] = []
            var selectedAmount = Value()

            for input in inputs {
                selectedUtxos.append(input)
                selectedAmount += input.output.amount
            }

            if let mint = mint {
                // Add positive minted amounts to the selected amount (=source)
                for (pid, m) in mint.data {
                    for (tkn, am) in m.data {
                        if am > 0 {
                            selectedAmount += Value(
                                multiAsset: MultiAsset([pid: Asset([tkn: am])])
                            )
                        }
                    }
                }
            }

            if let withdrawals = withdrawals {
                for withdrawal in withdrawals.data.values {
                    selectedAmount.coin += Int(withdrawal)
                }
            }

            var canMergeChange = false
            if mergeChange {
                for output in outputs {
                    if output.address == changeAddress {
                        canMergeChange = true
                        break
                    }
                }
            }

            selectedAmount.coin -= try await getTotalKeyDeposit()
            selectedAmount.coin -= getTotalProposalDeposit()

            var requestedAmount = Value()
            for output in outputs {
                requestedAmount += output.amount
            }

            if let mint = mint {
                // Add negative minted amounts to the requested amount (=sink)
                for (pid, m) in mint.data {
                    for (tkn, am) in m.data {
                        if am < 0 {
                            requestedAmount += Value(
                                multiAsset: MultiAsset([pid: Asset([tkn: -am])])
                            )
                        }
                    }
                }
            }

            // Include min fees associated as part of requested amount
            await requestedAmount.coin += try estimateFee()

            // Trim off assets that are not requested because they will be returned as changes eventually
            var trimmedSelectedAmount = Value(coin: selectedAmount.coin)
            trimmedSelectedAmount.multiAsset = try selectedAmount.multiAsset
                .filter { pid, name, _ in
                    requestedAmount.multiAsset[pid]?[name] != nil
                }
            if !selectedAmount.multiAsset.isEmpty {
                trimmedSelectedAmount.multiAsset = try selectedAmount.multiAsset
                    .filter { pid, name, _ in
                        requestedAmount.multiAsset[pid]?[name] != nil
                    }
            }

            var unfulfilledAmount = requestedAmount - trimmedSelectedAmount

            if let changeAddress = changeAddress,
                !canMergeChange
            {
                // If change address is provided and remainder is smaller than minimum ADA required in change,
                // we need to select additional UTxOs available from the address
                if unfulfilledAmount.coin < 0 {
                    let minLovelace = try await minLovelacePostAlonzo(
                        TransactionOutput(
                            address: changeAddress,
                            amount: selectedAmount - trimmedSelectedAmount
                        ),
                        context
                    )
                    unfulfilledAmount.coin = max(
                        0,
                        unfulfilledAmount.coin + Int(minLovelace)
                    )
                }
            } else {
                unfulfilledAmount.coin = max(0, unfulfilledAmount.coin)
            }

            if !unfulfilledAmount.multiAsset.isEmpty {
                unfulfilledAmount.multiAsset = try unfulfilledAmount.multiAsset
                    .filter { _, _, value in value > 0 }
            }

            // Create a set of all seen utxos in addition to other utxo lists.
            // We need this set to avoid adding the same utxo twice.
            // The reason of not turning all utxo lists into sets is that we want to keep the order of utxos and make
            // utxo selection deterministic.
            var seenUtxos = Set(selectedUtxos)

            // When there are positive coin or native asset quantity in unfulfilled Value
            // Check if we need additional UTxOs - either for ADA or multi-assets
            let needsAdditionalUtxos = unfulfilledAmount.coin > 0 || !unfulfilledAmount.multiAsset.isEmpty
            
            if needsAdditionalUtxos {
                var additionalUtxoPool: [UTxO] = []
                var additionalAmount = Value()

                for utxo in potentialInputs {
                    additionalAmount += utxo.output.amount
                    seenUtxos.insert(utxo)
                    additionalUtxoPool.append(utxo)
                }

                for address in inputAddresses {
                    let utxos = try await context.utxos(address: address.asAddress!)
                    for utxo in utxos {
                        if !seenUtxos.contains(utxo) && !excludedInputs.contains(utxo) {
                            additionalUtxoPool.append(utxo)
                            additionalAmount += utxo.output.amount
                            seenUtxos.insert(utxo)
                        }
                    }
                }

                for (index, selector) in utxoSelectors.enumerated() {
                    do {
                        let (selected, _) = try await selector.select(
                            utxos: additionalUtxoPool,
                            outputs: [
                                TransactionOutput(
                                    address: Address(paymentPart: .verificationKeyHash(TxBuilder.FAKE_VKEY.hash())),
                                    amount: unfulfilledAmount
                                )
                            ],
                            context: context,
                            maxInputCount: nil,
                            includeMaxFee: false,
                            respectMinUtxo: !mergeChange
                        )

                        for s in selected {
                            selectedAmount += s.output.amount
                            selectedUtxos.append(s)
                        }
                        
                        break // Break out of the loop after successful selection
                    }
                    catch {
                        if index < utxoSelectors.count - 1 {
                            logger.info("\(error)")
                            logger.info("\(selector) failed. Trying next selector.")
                            continue
                        } else {
                            var trimmedAdditionalAmount = Value(coin: additionalAmount.coin)
                            if !additionalAmount.multiAsset.isEmpty {
                                trimmedAdditionalAmount.multiAsset = try additionalAmount.multiAsset
                                    .filter { pid, name, _ in
                                        requestedAmount.multiAsset[pid]?[name] != nil
                                    }
                            }

                            var diff = requestedAmount - trimmedSelectedAmount - trimmedAdditionalAmount
                            if !diff.multiAsset.isEmpty {
                                diff.multiAsset = try diff.multiAsset
                                    .filter { _, _, value in value > 0 }
                            }

                            throw CardanoTxBuilderError.utxoSelectionFailed(
                                "All UTxO selectors failed.\n"
                                    + "Requested output:\n \(requestedAmount) \n"
                                    + "Pre-selected inputs:\n \(selectedAmount) \n"
                                    + "Additional UTxO pool:\n \(additionalUtxoPool) \n"
                                    + "Unfulfilled amount:\n \(diff)"
                            )
                        }
                    }
                }
            }

            selectedUtxos.sort { a, b in
                let aId = a.input.transactionId.description
                let bId = b.input.transactionId.description
                return aId == bId ? a.input.index < b.input.index : aId < bId
            }

            _inputs = selectedUtxos

            // Automatically set the required signers for smart transactions
            if (isSmart && autoRequiredSigners != false) && requiredSigners == nil {
                // Collect all signatories from explicitly defined
                // transaction inputs and collateral inputs, and input addresses
                requiredSigners = Array(inputVkeyHashes())
            }

            try setRedeemerIndex()

            try await setCollateralReturn(collateralChangeAddress ?? changeAddress)

            try await updateExecutionUnits(
                changeAddress: changeAddress,
                mergeChange: mergeChange,
                collateralChangeAddress: collateralChangeAddress
            )

            try await addChangeAndFee(changeAddress: changeAddress, mergeChange: mergeChange)
            
            let txBody = try await buildTxBody()
            
            logState(logLevel: .debug)

            return txBody
        }
        catch {
            logState(logLevel: .warning)
            throw error
        }
    }

    /// Build a transaction body and sign it with the provided signing keys.
    /// - Parameters:
    ///   - signingKeys: The signing keys to use
    ///   - changeAddress: Address to which changes will be returned
    ///   - mergeChange: If true and the change address matches a transaction output, merge the change into that output
    ///   - collateralChangeAddress: Address to which collateral changes will be returned
    ///   - autoValidityStartOffset: Automatically set validity start interval (default -1000)
    ///   - autoTtlOffset: Automatically set validity end interval (default 10_000)
    ///   - autoRequiredSigners: Automatically add input pubkeyhashes to required signers
    ///   - forceSkeys: Whether to force using all signing keys even if not required
    /// - Returns: A signed transaction
    /// - Throws: CardanoTxBuilderError if the transaction cannot be built or signed
    public func buildAndSign(
        signingKeys: [SigningKeyType],
        changeAddress: Address? = nil,
        mergeChange: Bool = false,
        collateralChangeAddress: Address? = nil,
        autoValidityStartOffset: Int? = nil,
        autoTtlOffset: Int? = nil,
        autoRequiredSigners: Bool? = nil,
        forceSkeys: Bool = false
    ) async throws -> Transaction {
        // The given signers should be required signers if they weren't added yet
        if autoRequiredSigners == true && !allScripts.isEmpty && requiredSigners == nil {
            // Collect all signatories from explicitly defined
            // transaction inputs and collateral inputs, and input addresses
            requiredSigners = try signingKeys.map {
                try $0.toVerificationKey().hash()
            }
        }

        let txBody = try await build(
            changeAddress: changeAddress,
            mergeChange: mergeChange,
            collateralChangeAddress: collateralChangeAddress,
            autoValidityStartOffset: autoValidityStartOffset,
            autoTtlOffset: autoTtlOffset,
            autoRequiredSigners: autoRequiredSigners
        )

        var witnessSet = try buildWitnessSet(removeDupScript: true)
        var vkeyWitnesses = [] as [VerificationKeyWitness]

        let requiredVkeys = try buildRequiredVkeys()

        for signingKey in Set(signingKeys) {
            let vkey: any VerificationKeyProtocol = try signingKey.toVerificationKey()
            let vkeyHash: VerificationKeyHash = try vkey.hash()
            let vkeyType: VerificationKeyType = try signingKey.toVerificationKeyType()

            if !forceSkeys && !requiredVkeys.contains(vkeyHash) {
                logger.warning("Verification key hash \(vkeyHash) is not required for this tx.")
                continue
            }

            let signature = try signingKey.sign(data: txBody.hash())

            vkeyWitnesses.append(
                VerificationKeyWitness(
                    vkey: vkeyType,
                    signature: signature
                )
            )
        }

        if vkeyWitnesses.isEmpty == true {
            witnessSet.vkeyWitnesses = nil
        } else {
            witnessSet.vkeyWitnesses =
                .nonEmptyOrderedSet(NonEmptyOrderedSet(vkeyWitnesses))
        }

        return Transaction(
            transactionBody: txBody,
            transactionWitnessSet: witnessSet,
            valid: true,
            auxiliaryData: auxiliaryData
        )
    }

    // MARK: - Private Methods
    
    /// Check if the provided Value can cover the requested Value
    /// - Parameters:
    ///   - provided: The Value being provided (from inputs, minting, withdrawals)
    ///   - requested: The Value being requested (for outputs and fees)
    /// - Returns: True if provided can cover requested
    private func canCoverRequested(provided: Value, requested: Value) -> Bool {
        // First check if coins are sufficient
        guard provided.coin >= requested.coin else {
            return false
        }
        
        // Then check if all multi-assets are covered
        for (policyId, requestedAsset) in requested.multiAsset.data {
            guard let providedAsset = provided.multiAsset.data[policyId] else {
                // Missing policy ID in provided
                return false
            }
            
            for (assetName, requestedAmount) in requestedAsset.data {
                let providedAmount = providedAsset.data[assetName] ?? 0
                guard providedAmount >= requestedAmount else {
                    return false
                }
            }
        }
        
        return true
    }

    private func consolidateRedeemer(_ redeemer: inout Redeemer) throws {
        if _shouldEstimateExecutionUnits == nil {
            if redeemer.exUnits != nil {
                _shouldEstimateExecutionUnits = false
            } else {
                _shouldEstimateExecutionUnits = true
                redeemer.exUnits = ExecutionUnits(mem: 0, steps: 0)
            }
        } else {
            if !_shouldEstimateExecutionUnits! && redeemer.exUnits == nil {
                throw CardanoTxBuilderError.invalidInput(
                    "All redeemers need to provide execution units if the firstly "
                        + "added redeemer specifies execution units.\n"
                        + "Added redeemers: \(_redeemerList)\n" + "New redeemer: \(redeemer)"
                )
            }
            if _shouldEstimateExecutionUnits! {
                if redeemer.exUnits != nil {
                    throw CardanoTxBuilderError.invalidInput(
                        "No redeemer should provide execution units if the firstly "
                            + "added redeemer didn't provide execution units.\n"
                            + "Added redeemers: \(_redeemerList)\n" + "New redeemer: \(redeemer)"
                    )
                } else {
                    redeemer.exUnits = ExecutionUnits(mem: 0, steps: 0)
                }
            }
        }
    }

    private func calcChange(
        fees: Int,
        inputs: [UTxO],
        outputs: [TransactionOutput],
        address: Address,
        preciseFee: Bool = false,
        respectMinUtxo: Bool = true
    ) async throws -> [TransactionOutput] {
        var requested = Value(coin: fees)
        for output in outputs {
            requested += output.amount
        }

        var provided = Value()
        for input in inputs {
            provided += input.output.amount
        }

        if let mint = mint {
            provided.multiAsset += mint
        }

        if let withdrawals = withdrawals {
            for withdrawal in withdrawals.data.values {
                provided.coin += Int(withdrawal)
            }
        }

        provided.coin -= try await getTotalKeyDeposit()
        provided.coin -= getTotalProposalDeposit()

        guard canCoverRequested(provided: provided, requested: requested) else {
            print("Requested: \(requested)")
            print("Provided: \(provided)")
            throw CardanoTxBuilderError.invalidTransaction(
                "The input UTxOs cannot cover the transaction outputs and tx fee.\n"
                    + "Inputs: \(inputs)\n" + "Outputs: \(outputs)\n" + "fee: \(fees)"
            )
        }

        var change = provided - requested

        // Remove any asset that has 0 quantity
        if !change.multiAsset.isEmpty {
            change.multiAsset = try change.multiAsset
                .filter { _, _, value in value > 0 }
        }

        var changeOutputs: [TransactionOutput] = []

        // When there is only ADA left, simply use remaining coin value as change
        if change.multiAsset.isEmpty {
            if respectMinUtxo {
                let minLovelace = try await minLovelacePostAlonzo(
                    TransactionOutput(address: address, amount: change),
                    context
                )
                guard change.coin > minLovelace else {
                    throw CardanoTxBuilderError.insufficientUTxOBalance(
                        "Not enough ADA left for change: \(change.coin) but needs \(minLovelace)"
                    )
                }
            }
            let lovelaceChange = Value(coin: change.coin)
            changeOutputs.append(TransactionOutput(address: address, amount: lovelaceChange))
        }

        // If there are multi assets in the change
        if !change.multiAsset.isEmpty {
            // Split assets if size exceeds limits
            let protocolParameters = try await context.protocolParameters()
            let multiAssetArray = try await packTokensForChange(
                address: address,
                change: change,
                maxValSize: protocolParameters.maxValueSize
            )

            // Include minimum lovelace into each token output except for the last one
            for (i, multiAsset) in multiAssetArray.enumerated() {
                // Combine remainder of provided ADA with last MultiAsset for output
                // There may be rare cases where adding ADA causes size exceeds limit
                // We will revisit if it becomes an issue
                if respectMinUtxo {
                    let minLovelace = try await minLovelacePostAlonzo(
                        TransactionOutput(
                            address: address,
                            amount: Value(
                                coin: 0, multiAsset: multiAsset)
                        ),
                        context
                    )
                    
                    guard change.coin > minLovelace else {
                        throw CardanoTxBuilderError.insufficientBalance(
                            "Not enough ADA left to cover non-ADA assets in a change address"
                        )
                    }
                }

                var changeValue: Value
                if i == multiAssetArray.count - 1 {
                    // Include all ada in last output
                    changeValue = Value(
                        coin: change.coin,
                        multiAsset: multiAsset
                    )
                } else {
                    changeValue = Value(
                        coin: 0,
                        multiAsset: multiAsset
                    )
                    changeValue.coin = Int(
                        try await minLovelacePostAlonzo(
                            TransactionOutput(
                                address: address,
                                amount: changeValue
                            ),
                            context
                        )
                    )
                }

                changeOutputs.append(TransactionOutput(address: address, amount: changeValue))
                change -= changeValue
                if !change.multiAsset.isEmpty {
                    change.multiAsset = try change.multiAsset
                        .filter { _, _, value in value > 0 }
                }
            }
        }

        return changeOutputs
    }

    private func getTotalKeyDeposit() async throws -> Int {
        var stakeRegistrationCerts = Set<StakeCredential>()
        var stakeRegistrationCertsWithExplicitDeposit = Set<Int>()
        var stakePoolRegistrationCerts = Set<PoolKeyHash>()

        let protocolParameters = try await context.protocolParameters()

        if let certificates = certificates {
            for cert in certificates {
                switch cert {
                    case .stakeRegistration(let reg):
                        stakeRegistrationCerts.insert(
                            StakeCredential(credential: reg.stakeCredential.credential)
                        )
                    case .registerDRep(let reg):
                        stakeRegistrationCertsWithExplicitDeposit.insert(Int(reg.coin))
                    case .register(let reg):
                        stakeRegistrationCertsWithExplicitDeposit.insert(Int(reg.coin))
                    case .stakeRegisterDelegate(let reg):
                        stakeRegistrationCertsWithExplicitDeposit.insert(Int(reg.coin))
                    case .voteRegisterDelegate(let reg):
                        stakeRegistrationCertsWithExplicitDeposit.insert(Int(reg.coin))
                    case .stakeVoteRegisterDelegate(let reg):
                        stakeRegistrationCertsWithExplicitDeposit.insert(Int(reg.coin))
                    case .poolRegistration(let poolReg):
                        if initialStakePoolRegistration {
                            stakePoolRegistrationCerts.insert(poolReg.poolParams.poolOperator)
                        }
                    default:
                        break
                }
            }
        }

        let stakeRegistrationDeposit =
            protocolParameters.stakeAddressDeposit * stakeRegistrationCerts.count
            + stakeRegistrationCertsWithExplicitDeposit.reduce(0, +)
        let stakePoolRegistrationDeposit =
            protocolParameters.stakePoolDeposit * stakePoolRegistrationCerts.count

        return stakeRegistrationDeposit + stakePoolRegistrationDeposit
    }

    private func getTotalProposalDeposit() -> Int {
        guard let proposalProcedures = proposalProcedures else { return 0 }
        return Int(proposalProcedures.elements.reduce(0) { $0 + $1.deposit })
    }

    private func addingAssetMakeOutputOverflow(
        output: TransactionOutput,
        currentAssets: Asset,
        policyId: ScriptHash,
        addAssetName: AssetName,
        addAssetVal: Int,
        maxValSize: Int
    ) async throws -> Bool {
        var attemptAssets = currentAssets
        attemptAssets += Asset([addAssetName: addAssetVal])
        let attemptMultiAsset = MultiAsset([policyId: attemptAssets])

        let newAmount = Value(coin: 0, multiAsset: attemptMultiAsset)
        let currentAmount = output.amount
        var attemptAmount = newAmount + currentAmount

        // Calculate minimum ada requirements for more precise value size
        let requiredLovelace = try await minLovelacePostAlonzo(
            TransactionOutput(address: output.address, amount: attemptAmount),
            context
        )
        attemptAmount.coin = Int(requiredLovelace)

        return try attemptAmount.toCBORData().count > maxValSize
    }

    private func packTokensForChange(
        address: Address,
        change: Value,
        maxValSize: Int
    ) async throws -> [MultiAsset] {
        var multiAssetArray: [MultiAsset] = []
        let baseCoin = Value(coin: change.coin)
        var output = TransactionOutput(address: address, amount: baseCoin)

        // Iteratively add tokens to output
        if !change.multiAsset.isEmpty {
            for (policyId, assets) in change.multiAsset.data {
                var tempMultiAsset = MultiAsset([:])
                var tempValue = Value(coin: 0)
                var tempAssets = Asset([:])
                let oldAmount = output.amount

                for (assetName, assetValue) in assets.data {
                    if try await addingAssetMakeOutputOverflow(
                        output: output,
                        currentAssets: tempAssets,
                        policyId: policyId,
                        addAssetName: assetName,
                        addAssetVal: assetValue,
                        maxValSize: maxValSize
                    ) {
                        // Insert current assets as one group if current assets isn't null
                        // This handles edge case when first Asset from next policy will cause overflow
                        if !tempAssets.data.isEmpty {
                            tempMultiAsset += MultiAsset([policyId: tempAssets])
                            tempValue.multiAsset = tempMultiAsset
                            output.amount += tempValue
                        }
                        multiAssetArray.append(output.amount.multiAsset)

                        // Create a new output
                        let baseCoin = Value(coin: 0)
                        output = TransactionOutput(address: address, amount: baseCoin)

                        // Continue building output from where we stopped
                        tempMultiAsset = MultiAsset([:])
                        tempValue = Value()
                        tempAssets = Asset([:])
                    }

                    tempAssets += Asset([assetName: assetValue])
                }

                // Assess assets in buffer
                tempMultiAsset += MultiAsset([policyId: tempAssets])
                tempValue.multiAsset = tempMultiAsset
                output.amount += tempValue

                // Calculate min lovelace required for more precise size
                var updatedAmount = output.amount
                let requiredLovelace = try await minLovelacePostAlonzo(
                    TransactionOutput(address: address, amount: updatedAmount),
                    context
                )
                updatedAmount.coin = Int(requiredLovelace)

                if try updatedAmount.toCBORData().count > maxValSize {
                    output.amount = oldAmount
                    break
                }
            }
        }

        if !output.amount.multiAsset.isEmpty {
            multiAssetArray.append(output.amount.multiAsset)
        }

        // Remove records where MultiAsset is null due to overflow of adding
        // items at the beginning of next policy to previous policy MultiAssets
        return multiAssetArray.filter { !$0.isEmpty }
    }

    private func ensureNoInputExclusionConflict() throws {
        let intersection = Set(inputs).intersection(Set(excludedInputs))
        if !intersection.isEmpty {
            throw CardanoTxBuilderError.invalidInput(
                "Found common UTxOs between UTxO inputs and UTxO excluded_inputs: \(intersection)"
            )
        }
    }

    private func refScriptSize() throws -> Int {
        try _referenceScripts.reduce(into: 0) { size, script in
            switch script {
                case .nativeScript(let script):
                    size += try script.toCBORData().count
                case .plutusV1Script(let script):
                    size += script.data.count
                case .plutusV2Script(let script):
                    size += script.data.count
                case .plutusV3Script(let script):
                    size += script.data.count
            }
        }
    }

    private func estimateFee() async throws -> Int {
        var plutusExecutionUnits = ExecutionUnits(mem: 0, steps: 0)
        for redeemer in _redeemerList {
            if let exUnits = redeemer.exUnits {
                plutusExecutionUnits += exUnits
            }
        }

        var estimatedFee = try await calculateFee(
            context,
            length: UInt64(buildFullFakeTx().toCBORData().count),
            execSteps: UInt64(plutusExecutionUnits.steps),
            maxMemUnit: UInt64(plutusExecutionUnits.mem),
            refScriptSize: UInt64(refScriptSize())
        )
        
        if feeBuffer != nil {
            estimatedFee += UInt64(feeBuffer!)
        }
        
        return Int(estimatedFee)
    }

    private func buildTxBody() async throws -> TransactionBody {
        let txBody = TransactionBody(
            inputs:
                    .orderedSet(
                        try OrderedSet<TransactionInput>(
                            Set(inputs.map { $0.input })
                        )
                    ),
            outputs: outputs,
            fee: Coin(fee),
            ttl: ttl,
//            certificates: certificates == nil || certificates!.isEmpty
//            ? nil : .nonEmptyOrderedSet(
//                NonEmptyOrderedSet<Certificate>(certificates!)
//            ),
            certificates: certificates == nil || certificates!.isEmpty ? nil : .list(certificates!),
            withdrawals: withdrawals,
            update: nil,
            auxiliaryDataHash: try auxiliaryData?.hash(),
            validityStart: validityStart,
            mint: mint,
            scriptDataHash: try await scriptDataHash(),
            collateral: collaterals.isEmpty
            ? nil : .nonEmptyOrderedSet(
                NonEmptyOrderedSet<TransactionInput>(
                    collaterals.map { $0.input
                    })
            ),
            requiredSigners: requiredSigners == nil || requiredSigners!.isEmpty
            ? nil : .nonEmptyOrderedSet(NonEmptyOrderedSet(requiredSigners!)),
            collateralReturn: _collateralReturn,
            totalCollateral: _totalCollateral == nil ? nil : Coin(_totalCollateral!),
            referenceInputs: referenceInputs.isEmpty
                ? nil
            : .nonEmptyOrderedSet(NonEmptyOrderedSet<TransactionInput>(
                    referenceInputs.map { input in
                        switch input {
                        case .utxo(let utxo): return utxo.input
                        case .input(let input): return input
                        }
                    }
                )),
            votingProcedures: votingProcedures == nil ? nil : votingProcedures!,
            proposalProcedures: proposalProcedures == nil ? nil : proposalProcedures!,
            currentTreasuryAmount: currentTreasuryValue == nil ? nil : Coin(currentTreasuryValue!),
            treasuryDonation: donation == nil
                ? nil
                : PositiveCoin(
                    UInt(donation!)
                )
        )
        return txBody
    }

    private func buildFullFakeTx() async throws -> Transaction {
        var txBody = try await buildTxBody()

        if txBody.fee == 0 {
            // When fee is not specified, we will use max possible fee to fill in the fee field.
            // This will make sure the size of fee field itself is taken into account during fee estimation.
            txBody.fee = try await maxTxFee(context)
        }

        let witness = try buildFakeWitnessSet()
        let tx = Transaction(
            transactionBody: txBody,
            transactionWitnessSet: witness,
            valid: true,
            auxiliaryData: auxiliaryData
        )

        let protocolParameters = try await context.protocolParameters()
        
        let size = try tx.toCBORData().count

        if size > protocolParameters.maxTxSize {
            throw CardanoTxBuilderError.transactionTooLarge(
                "Transaction size (\(try tx.toCBORData().count)) exceeds the max limit "
                    + "(\(protocolParameters.maxTxSize)). Please try reducing the "
                    + "number of inputs or outputs."
            )
        }

        return tx
    }

    private func buildFakeWitnessSet() throws -> TransactionWitnessSet {
        var witnessSet = try! buildWitnessSet(removeDupScript: true)
        if try witnessCount() > 0 {
            witnessSet.vkeyWitnesses =
                .nonEmptyOrderedSet(try buildFakeVkeyWitnesses())
        }
        return witnessSet
    }

    private func buildFakeVkeyWitnesses() throws -> NonEmptyOrderedSet<VerificationKeyWitness> {
        var witnesses: [VerificationKeyWitness] = []
        let witnessCount = try witnessCount()
        let fakeVKeyBytes = Array(TxBuilder.FAKE_VKEY.payload)
        let fakeSigBytes = Array(TxBuilder.FAKE_TX_SIGNATURE)

        for i in 0..<witnessCount {
            // Convert index to 32-byte array (big endian)
            var iBytes = [UInt8](repeating: 0, count: 32)
            for j in 0..<8 {
                iBytes[31 - j] = UInt8((i >> (j * 8)) & 0xFF)
            }

            // Create a unique vkey by ANDing the fake vkey bytes with iBytes
            let uniqueVKeyBytes = zip(fakeVKeyBytes, iBytes).map { $0 & $1 }
            let uniqueVKey = try VerificationKey(payload: Data(uniqueVKeyBytes))

            // Create a unique signature by ANDing the fake signature bytes with iBytes + iBytes (64 bytes)
            let doubledIBytes = iBytes + iBytes
            let uniqueSigBytes = zip(fakeSigBytes, doubledIBytes).map { $0 & $1 }

            witnesses.append(
                VerificationKeyWitness(
                    vkey: .verificationKey(uniqueVKey),
                    signature: Data(uniqueSigBytes)
                )
            )
        }

        return NonEmptyOrderedSet(witnesses)
    }

    private func witnessCount() throws -> Int {
        let requiredVkeys = try buildRequiredVkeys().count
        return witnessOverride ?? requiredVkeys
    }

    private func buildRequiredVkeys() throws -> Set<VerificationKeyHash> {
        var vkeyHashes = inputVkeyHashes()
        vkeyHashes.formUnion(requiredSignerVkeyHashes())
        vkeyHashes.formUnion(nativeScriptsVkeyHashes())
        vkeyHashes.formUnion(certificateVkeyHashes())
        vkeyHashes.formUnion(try withdrawalVkeyHashes())
        vkeyHashes.formUnion(voteVkeyHashes())
        return vkeyHashes
    }

    private func inputVkeyHashes() -> Set<VerificationKeyHash> {
        var results = Set<VerificationKeyHash>()
        for input in inputs + collaterals {
            if case .verificationKeyHash(let vkeyHash) = input.output.address.paymentPart {
                results.insert(vkeyHash)
            }
        }
        return results
    }

    private func requiredSignerVkeyHashes() -> Set<VerificationKeyHash> {
        Set(requiredSigners ?? [])
    }

    private func nativeScriptsVkeyHashes() -> Set<VerificationKeyHash> {
        var results = Set<VerificationKeyHash>()

        func dfs(_ script: NativeScript) -> Set<VerificationKeyHash> {
            var tmp = Set<VerificationKeyHash>()
            switch script {
            case .scriptPubkey(let nativeScript):
                tmp.insert(nativeScript.keyHash)
            case .scriptAll(let scripts):
                for s in scripts.scripts {
                    tmp.formUnion(dfs(s))
                }
            case .scriptAny(let scripts):
                for s in scripts.scripts {
                    tmp.formUnion(dfs(s))
                }
            default:
                break
            }
            return tmp
        }

        if let nativeScripts = nativeScripts {
            for script in nativeScripts {
                results.formUnion(dfs(script))
            }
        }

        return results
    }

    private func certificateVkeyHashes() -> Set<VerificationKeyHash> {
        var results = Set<VerificationKeyHash>()

        func checkAndAddVkey(_ credential: any Credential) {
            if case .verificationKeyHash(let vkeyHash) = credential.credential {
                results.insert(vkeyHash)
            }
        }

        if let certificates = certificates {
            for cert in certificates {
                switch cert {
                case .stakeRegistration(let reg):
                    checkAndAddVkey(reg.stakeCredential)
                case .stakeDeregistration(let dereg):
                    checkAndAddVkey(dereg.stakeCredential)
                case .stakeDelegation(let del):
                    checkAndAddVkey(del.stakeCredential)
                case .register(let regConway):
                    checkAndAddVkey(regConway.stakeCredential)
                case .unregister(let deregConway):
                    checkAndAddVkey(deregConway.stakeCredential)
                case .voteDelegate(let voteDel):
                    checkAndAddVkey(voteDel.stakeCredential)
                case .stakeVoteDelegate(let stakeAndVoteDel):
                    checkAndAddVkey(stakeAndVoteDel.stakeCredential)
                case .stakeRegisterDelegate(let stakeAndRegDel):
                    checkAndAddVkey(stakeAndRegDel.stakeCredential)
                case .voteRegisterDelegate(let voteAndRegDel):
                    checkAndAddVkey(voteAndRegDel.stakeCredential)
                case .stakeVoteRegisterDelegate(let stakeAndVoteAndRegDel):
                    checkAndAddVkey(stakeAndVoteAndRegDel.stakeCredential)
                case .registerDRep(let regDRep):
                    checkAndAddVkey(regDRep.drepCredential)
                case .poolRegistration(let poolReg):
                    results
                        .insert(
                            VerificationKeyHash(
                                payload: poolReg.poolParams.vrfKeyHash.payload
                            )
                        )
                case .poolRetirement(let poolRet):
                    results
                        .insert(
                            VerificationKeyHash(
                                payload: poolRet.poolKeyHash.payload
                            )
                        )
                default:
                    break
                }
            }
        }
        return results
    }

    private func withdrawalVkeyHashes() throws -> Set<VerificationKeyHash> {
        var results = Set<VerificationKeyHash>()

        if let withdrawals = withdrawals {
            for key in withdrawals.data.keys {
                let address = try Address(from: .bytes(key))
                if address.addressType == .noneKey {
                    if case .verificationKeyHash(let vkeyHash) = address.stakingPart {
                        results.insert(vkeyHash)
                    }
                }
            }
        }

        return results
    }

    private func voteVkeyHashes() -> Set<VerificationKeyHash> {
        var results = Set<VerificationKeyHash>()

        if let votingProcedures = votingProcedures?.allVotes {
            for votingProcedure in votingProcedures {
                let voter = votingProcedure.0
                switch voter.credential {
                    case .constitutionalCommitteeHotKeyhash(let vkeyHash):
                        results.insert(vkeyHash)
                    case .drepKeyhash(let vkeyHash):
                        results.insert(vkeyHash)
                    case .stakePoolKeyhash(let vkeyHash):
                        results.insert(vkeyHash)
                    default:
                        break
                }
            }
        }

        return results
    }

    private func scriptDataHash() async throws -> ScriptDataHash? {
        if !datums.isEmpty || !_redeemerList.isEmpty {
            var costModels: [Int: [Int]] = [:]
            for script in allScripts {
                var version = -1
                switch script {
                    case .plutusV1Script(let plutusScript):
                        version = plutusScript.version
                    case .plutusV2Script(let plutusScript):
                        version = plutusScript.version
                    case .plutusV3Script(let plutusScript):
                        version = plutusScript.version
                    case .nativeScript(_):
                        version = 1
                }

                let protocolParams = try await context.protocolParameters()
                if version != -1 {
                    costModels[version - 1] = protocolParams.costModels.getVersion(version)
                }
            }
            return try Utils.scriptDataHash(
                redeemers: try redeemers(),
                datums: Array(datums.values),
                costModels: CostModels(costModels)
            )
        }
        return nil
    }

    private func setRedeemerIndex() throws {
        // Set redeemers' index according to section 4.1 in
        // https://hydra.iohk.io/build/13099856/download/1/alonzo-changes.pdf
        //
        // There is no way to determine certificate index here

        let sortedMintPolicies = try mint?.data.keys.sorted {
            let a = try $0.toCBORHex()
            let b = try $1.toCBORHex()
            return a < b
        } ?? []
        let sortedWithdrawals = withdrawals?.data.keys.sorted { $0.toHex < $1.toHex } ?? []

        // Set spend redeemer indices
        for (i, utxo) in inputs.enumerated() {
            if let redeemer = _inputsToRedeemers[utxo],
                redeemer.tag == .spend
            {
                _inputsToRedeemers[utxo]?.index = i
            }
        }

        // Set mint redeemer indices
        for (script, redeemer) in _mintingScriptToRedeemers {
            if redeemer != nil {
                if let index = sortedMintPolicies.firstIndex(of: try! scriptHash(script: script)) {
                    _mintingScriptToRedeemers = _mintingScriptToRedeemers.map { (s, r) in
                        if s == script {
                            var newRedeemer = r
                            newRedeemer?.index = index
                            return (s, newRedeemer)
                        }
                        return (s, r)
                    }
                }
            }
        }

        // Set withdrawal redeemer indices
        for (script, redeemer) in _withdrawalScriptToRedeemers {
            if var redeemer = redeemer {
                let scriptStakingCredential = try Address(
                    stakingPart: .scriptHash(try! scriptHash(script: script)),
                    network: context.networkId
                )
                
                if let index = sortedWithdrawals.firstIndex(of: scriptStakingCredential.toBytes())
                {
                    redeemer.index = index
                    // Update the array with the modified redeemer
                    _withdrawalScriptToRedeemers = _withdrawalScriptToRedeemers.map { (s, r) in
                        if s == script {
                            return (s, redeemer)
                        }
                        return (s, r)
                    }
                }
            }
        }
    }

    /// Check if the collateral return should be added to the transaction
    /// - Parameter collateralReturn: The collateral return value
    /// - Returns: True if the collateral return should be added to the transaction
    private func shouldAddCollateralReturn(_ collateralReturn: Value) throws -> Bool {
        let a = collateralReturn.coin > max(collateralReturnThreshold, 1_000_000)
        let b = (try collateralReturn.multiAsset.count { _, _, v in v > 0 }) > 0
        return a || b
    }

    private func setCollateralReturn(_ collateralReturnAddress: Address?) async throws {
        let witnessSet = try buildWitnessSet()

        // Make sure there is at least one script input
        if witnessSet.plutusV1Script == nil && witnessSet.plutusV2Script == nil
            && witnessSet.plutusV3Script == nil && _referenceScripts.isEmpty
        {
            return
        }

        guard let collateralReturnAddress = collateralReturnAddress else {
            return
        }

        let protocolParameters = try await context.protocolParameters()

        let collateralAmount =
            Int(
                try await maxTxFee(
                    context,
                    refScriptSize: UInt64(refScriptSize())
                )) * protocolParameters.collateralPercentage / 100

        if collaterals.isEmpty {
            var tmpVal = Value()

            func addCollateralInput(
                _ curTotal: inout Value,
                _ candidateInputs: inout [UTxO]
            ) async throws {
                var curCollateralReturn = curTotal - Value(coin: collateralAmount)

                var a = curTotal.coin < collateralAmount
                var b = try shouldAddCollateralReturn(curCollateralReturn)
                var c = 0 <= curCollateralReturn.coin
                var d = try await minLovelacePostAlonzo(
                    TransactionOutput(
                        address: collateralReturnAddress, amount: curCollateralReturn),
                    context
                )

                while (a || b && c && curCollateralReturn.coin < d) && !candidateInputs.isEmpty {
                    let candidate = candidateInputs.removeLast()
                    if let addressType = candidate.output.address.addressType,
                       addressType != .scriptKey && addressType != .scriptScript && addressType != .scriptPointer && addressType != .scriptNone,
                       candidate.output.amount.coin > 2_000_000,
                       !collaterals.contains(candidate)
                    {
                        collaterals.append(candidate)
                        curTotal += candidate.output.amount
                        curCollateralReturn = curTotal - Value(coin: collateralAmount)
                    }
                    
                    // Recalculate conditions for next iteration
                    a = curTotal.coin < collateralAmount
                    b = try shouldAddCollateralReturn(curCollateralReturn)
                    c = 0 <= curCollateralReturn.coin
                    d = try await minLovelacePostAlonzo(
                        TransactionOutput(
                            address: collateralReturnAddress, amount: curCollateralReturn),
                        context
                    )
                }
            }

            var sortedInputs = try inputs.sorted {
                (try $0.output.toCBORData().count, -$0.output.amount.coin) < (
                    try $1.output.toCBORData().count, -$1.output.amount.coin
                )
            }
            
            
            try await addCollateralInput(&tmpVal, &sortedInputs)

            if tmpVal.coin < collateralAmount {
                var sortedInputs = try potentialInputs.sorted {
                    (try $0.output.toCBORData().count, -$0.output.amount.coin) < (
                        try $1.output.toCBORData().count, -$1.output.amount.coin
                    )
                }
                try await addCollateralInput(&tmpVal, &sortedInputs)
            }

            if tmpVal.coin < collateralAmount {
                let utxos = try await context.utxos(address: collateralReturnAddress)
                var sortedInputs = try utxos.sorted {
                    (try $0.output.toCBORData().count, -$0.output.amount.coin) < (
                        try $1.output.toCBORData().count, -$1.output.amount.coin
                    )
                }
                try await addCollateralInput(&tmpVal, &sortedInputs)
            }
        }

        var totalInput = Value()

        for utxo in collaterals {
            totalInput += utxo.output.amount
        }

        guard collateralAmount <= totalInput.coin else {
            throw CardanoTxBuilderError.insufficientBalance(
                "Minimum collateral amount \(collateralAmount) is greater than total "
                    + "provided collateral inputs \(totalInput)"
            )
        }

        let returnAmount = totalInput - Value(coin: collateralAmount)

        if try shouldAddCollateralReturn(returnAmount) == false {
            return  // No need to return collateral if the remaining amount is too small
        }

        let minLovelaceVal = try await minLovelacePostAlonzo(
            TransactionOutput(
                address: collateralReturnAddress,
                amount: returnAmount
            ),
            context
        )

        guard minLovelaceVal <= returnAmount.coin else {
            throw CardanoTxBuilderError.insufficientBalance(
                "Minimum lovelace amount for collateral return \(minLovelaceVal) is "
                    + "greater than collateral change \(returnAmount.coin). Please provide more collateral inputs."
            )
        }

        _collateralReturn = TransactionOutput(
            address: collateralReturnAddress,
            amount: totalInput - Value(coin: collateralAmount)
        )
        _totalCollateral = collateralAmount
    }

    private func updateExecutionUnits(
        changeAddress: Address?,
        mergeChange: Bool,
        collateralChangeAddress: Address?
    ) async throws {
        if _shouldEstimateExecutionUnits == true {
            let estimatedExecutionUnits = try await estimateExecutionUnits(
                changeAddress: changeAddress,
                mergeChange: mergeChange,
                collateralChangeAddress: collateralChangeAddress
            )

            for var redeemer in _redeemerList {
                guard let tag = redeemer.tag else {
                    throw CardanoTxBuilderError.invalidState(
                        "Expected tag of redeemer to be set, but found nil")
                }

                let tagname = tag.description()
                let key = "\(tagname):\(redeemer.index)"

                guard let exUnits = estimatedExecutionUnits[key] else {
                    throw CardanoTxBuilderError.invalidState(
                        "Cannot find execution unit for redeemer: \(redeemer) "
                            + "in estimated execution units: \(estimatedExecutionUnits)"
                    )
                }

                redeemer.exUnits = ExecutionUnits(
                    mem: Int(Double(exUnits.mem) * (1 + executionMemoryBuffer)),
                    steps: Int(Double(exUnits.steps) * (1 + executionStepBuffer))
                )
                
                // Update the redeemer in its original storage location
                switch tag {
                case .spend:
                    // Find and update the corresponding UTxO's redeemer
                    for (utxo, storedRedeemer) in _inputsToRedeemers {
                        if storedRedeemer.index == redeemer.index && storedRedeemer.tag == .spend {
                            _inputsToRedeemers[utxo] = redeemer
                            break
                        }
                    }
                case .mint:
                    // Update the minting script redeemer
                    _mintingScriptToRedeemers = _mintingScriptToRedeemers.map { (script, storedRedeemer) in
                        if let storedRedeemer = storedRedeemer,
                           storedRedeemer.index == redeemer.index && storedRedeemer.tag == .mint {
                            return (script, redeemer)
                        }
                        return (script, storedRedeemer)
                    }
                case .cert:
                    // Update the certificate script redeemer
                    _certificateScriptToRedeemers = _certificateScriptToRedeemers.map { (script, storedRedeemer) in
                        if let storedRedeemer = storedRedeemer,
                           storedRedeemer.index == redeemer.index && storedRedeemer.tag == .cert {
                            return (script, redeemer)
                        }
                        return (script, storedRedeemer)
                    }
                case .reward:
                    // Update the withdrawal script redeemer
                    _withdrawalScriptToRedeemers = _withdrawalScriptToRedeemers.map { (script, storedRedeemer) in
                        if let storedRedeemer = storedRedeemer,
                           storedRedeemer.index == redeemer.index && storedRedeemer.tag == .reward {
                            return (script, redeemer)
                        }
                        return (script, storedRedeemer)
                    }
                case .voting, .proposing:
                    // TODO: Add support for voting and proposing redeemers when storage is implemented
                    break
                }
            }
        }
    }

    private func estimateExecutionUnits(
        changeAddress: Address?,
        mergeChange: Bool,
        collateralChangeAddress: Address?
    ) async throws -> [String: ExecutionUnits] {
        // Create a deep copy of current builder, so we won't mess up current builder's internal states
        let tmpBuilder = self.copy()
        tmpBuilder._shouldEstimateExecutionUnits = false
        _shouldEstimateExecutionUnits = false

        let txBody = try await tmpBuilder.build(
            changeAddress: changeAddress,
            mergeChange: mergeChange,
            collateralChangeAddress: collateralChangeAddress
        )

        let witnessSet = try tmpBuilder.buildWitnessSet(removeDupScript: true)

        let tx = Transaction(
            transactionBody: txBody,
            transactionWitnessSet: witnessSet,
            valid: true,
            auxiliaryData: tmpBuilder.auxiliaryData
        )

        return try await context.evaluateTx(tx: tx)
    }

    private func addChangeAndFee(
        changeAddress: Address?,
        mergeChange: Bool
    ) async throws {
        let originalOutputs = outputs
        var changeOutputIndex: Int?

        func mergeChanges(_ changes: [TransactionOutput]) throws {
            if let idx = changeOutputIndex,
                changes.count == 1
            {
                // Add the leftover change to the TransactionOutput containing the change address
                _outputs[idx].amount += changes[0].amount
            } else {
                _outputs += changes
            }
        }

        if let changeAddress = changeAddress {
            if mergeChange {
                for (idx, output) in originalOutputs.enumerated() {
                    // Find any transaction outputs which already contain the change address
                    if changeAddress == output.address {
                        if changeOutputIndex == nil || output.amount.coin == 0 {
                            changeOutputIndex = idx
                        }
                    }
                }
            }

            // Set fee to max
            fee = try await estimateFee()
            let changes = try await calcChange(
                fees: fee,
                inputs: inputs,
                outputs: outputs,
                address: changeAddress,
                preciseFee: true,
                respectMinUtxo: !mergeChange
            )

            try mergeChanges(changes)
        }

        // With changes included, we can estimate the fee more precisely
        fee = try await estimateFee()

        if let changeAddress = changeAddress {
            _outputs = originalOutputs
            let changes = try await calcChange(
                fees: fee,
                inputs: inputs,
                outputs: outputs,
                address: changeAddress,
                preciseFee: true,
                respectMinUtxo: !mergeChange
            )

            try mergeChanges(changes)
        }
    }
}

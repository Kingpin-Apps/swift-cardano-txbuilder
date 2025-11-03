import SwiftCardanoCore

public extension TxBuilder.Transactions {
    
    /// Create a transaction that registers a stake address and delegates it to a pool operator.
    /// - Parameters:
    ///   - stakeVerificationKey: The stake verification key for the stake address to register
    ///   - poolOperator: The pool operator to delegate the stake address to
    ///   - feePaymentAddress: The address to pay the transaction fee and registration deposit from
    ///   - signingKeys: Optional signing keys to sign the transaction. If nil or empty, returns an unsigned transaction.
    /// - Returns: A transaction that registers the stake address and delegates it to the specified pool operator.
    /// - Throws: CardanoTxBuilderError if the transaction could not be created.
    func stakeAddressRegistrationAndDelegation(
        stakeVerificationKey: StakeVerificationKey,
        poolOperator: PoolOperator,
        feePaymentAddress: Address,
        signingKeys: [SigningKeyType]? = nil
    ) async throws -> Transaction {
        // 1. Derive stake address from the stake verification key
        let stakeAddress = try Address(
            stakingPart: .verificationKeyHash(try stakeVerificationKey.hash()),
            network: self.txBuilder.context.networkId
        )
        
        // 2. Check if stake address is already registered
        let stakeAddressInfo = try await self.txBuilder.context.stakeAddressInfo(
            address: stakeAddress
        )
        
        if !stakeAddressInfo.isEmpty,
           let info = stakeAddressInfo.first,
           let active = info.active,
           active,
           info.activeEpoch != nil {
            var errorMessage = "Stake-Address: \(stakeAddress) is already registered on the chain!"
            if let poolId = info.stakeDelegation {
                errorMessage += "\nAccount is currently delegated to Pool with ID: \(poolId)"
            }
            if let drepId = info.voteDelegation {
                errorMessage += "\nAccount is currently delegated to DRep with ID: \(drepId)"
            }
            throw CardanoTxBuilderError.invalidTransaction(errorMessage)
        }
        
        let protocolParams = try await self.txBuilder.context.protocolParameters()
        
        // 3. Create stake credential and registration & delegation certificate
        let stakeCredential = StakeCredential(
            credential: .verificationKeyHash(try stakeVerificationKey.hash())
        )
        let stakeRegisterDelegateCertificate = StakeRegisterDelegate(
            stakeCredential: stakeCredential,
            poolKeyHash: poolOperator.poolKeyHash,
            coin: Coin(protocolParams.stakeAddressDeposit)
        )
        
        // 4. Add UTxOs from fee payment address if not already present
        if self.txBuilder.inputs.isEmpty {
            self.txBuilder.addInputAddress(.address(feePaymentAddress))
        }
        
        // 5. Add the stake registration & delegation certificate
        self.txBuilder.certificates = [
            .stakeRegisterDelegate(stakeRegisterDelegateCertificate)
        ]
        
        // 6. Build and optionally sign the transaction
        if signingKeys == nil || signingKeys?.isEmpty == true {
            let txBody = try await self.txBuilder.build(
                changeAddress: feePaymentAddress
            )
            return Transaction(
                transactionBody: txBody,
                transactionWitnessSet: try self.txBuilder.buildWitnessSet(),
                auxiliaryData: self.txBuilder.auxiliaryData
            )
        } else if let signingKeys = signingKeys, !signingKeys.isEmpty {
            let transaction = try await self.txBuilder.buildAndSign(
                signingKeys: signingKeys,
                changeAddress: feePaymentAddress
            )
            return transaction
        } else {
            throw CardanoTxBuilderError.invalidTransaction(
                "No signing keys provided for transaction."
            )
        }
    }
}

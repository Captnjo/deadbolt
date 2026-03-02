import Foundation

/// Builds complete Solana transactions for common operations.
public actor TransactionBuilder {
    private let rpcClient: SolanaRPCClient
    private let jitoClient: JitoClient
    private let jupiterClient: JupiterClient
    private let sanctumClient: SanctumClient

    public init(
        rpcClient: SolanaRPCClient,
        jitoClient: JitoClient = JitoClient(),
        jupiterClient: JupiterClient = JupiterClient(),
        sanctumClient: SanctumClient = SanctumClient()
    ) {
        self.rpcClient = rpcClient
        self.jitoClient = jitoClient
        self.jupiterClient = jupiterClient
        self.sanctumClient = sanctumClient
    }

    /// Build and sign a Send SOL transaction with compute budget and Jito tip.
    public func buildSendSOL(
        from signer: TransactionSigner,
        to recipient: SolanaPublicKey,
        lamports: UInt64,
        computeUnitLimit: UInt32 = 200_000,
        computeUnitPrice: UInt64? = nil,
        tipLamports: UInt64 = JitoTip.defaultTipLamports
    ) async throws -> (transaction: Transaction, fees: TransactionFees) {
        let blockhash = try await rpcClient.getLatestBlockhash()

        // Get priority fee if not specified
        let priorityFee: UInt64
        if let specified = computeUnitPrice {
            priorityFee = specified
        } else {
            priorityFee = (try? await rpcClient.suggestPriorityFee()) ?? 1000
        }

        // Build instructions
        var instructions: [Instruction] = []

        // 1. Set compute unit limit
        instructions.append(ComputeBudgetProgram.setComputeUnitLimit(computeUnitLimit))

        // 2. Set compute unit price (priority fee)
        instructions.append(ComputeBudgetProgram.setComputeUnitPrice(priorityFee))

        // 3. SOL transfer
        instructions.append(SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: lamports))

        // 4. Jito tip
        if tipLamports > 0 {
            instructions.append(try JitoTip.tipInstruction(from: signer.publicKey, lamports: tipLamports))
        }

        // Build message and transaction
        let message = try Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: instructions
        )

        var transaction = Transaction(message: message)
        try await transaction.sign(with: signer)

        // Calculate fees
        let baseFee: UInt64 = 5000 // 5000 lamports per signature
        let (rawProduct, overflow) = UInt64(computeUnitLimit).multipliedReportingOverflow(by: priorityFee)
        let priorityFeeTotal = overflow ? UInt64.max / 1_000_000 : rawProduct / 1_000_000
        let fees = TransactionFees(
            baseFee: baseFee,
            priorityFee: priorityFeeTotal,
            tipAmount: tipLamports
        )

        return (transaction, fees)
    }

    /// Build and sign a Send SPL Token transaction with optional ATA creation, compute budget, and Jito tip.
    public func buildSendToken(
        from signer: TransactionSigner,
        to recipient: SolanaPublicKey,
        mint: SolanaPublicKey,
        amount: UInt64,
        decimals: UInt8,
        computeUnitLimit: UInt32 = 200_000,
        computeUnitPrice: UInt64? = nil,
        tipLamports: UInt64 = JitoTip.defaultTipLamports
    ) async throws -> (transaction: Transaction, fees: TransactionFees) {
        let blockhash = try await rpcClient.getLatestBlockhash()

        // Get priority fee if not specified
        let priorityFee: UInt64
        if let specified = computeUnitPrice {
            priorityFee = specified
        } else {
            priorityFee = (try? await rpcClient.suggestPriorityFee()) ?? 1000
        }

        // Derive ATAs
        let senderATA = try SolanaPublicKey.associatedTokenAddress(owner: signer.publicKey, mint: mint)
        let recipientATA = try SolanaPublicKey.associatedTokenAddress(owner: recipient, mint: mint)

        // Check if recipient ATA exists
        let recipientATAExists = try await rpcClient.getTokenAccountBalance(address: recipientATA.base58) != nil

        // Build instructions
        var instructions: [Instruction] = []

        // 1. Set compute unit limit
        instructions.append(ComputeBudgetProgram.setComputeUnitLimit(computeUnitLimit))

        // 2. Set compute unit price (priority fee)
        instructions.append(ComputeBudgetProgram.setComputeUnitPrice(priorityFee))

        // 3. Create recipient ATA if it doesn't exist
        if !recipientATAExists {
            instructions.append(try TokenProgram.createAssociatedTokenAccount(
                payer: signer.publicKey,
                owner: recipient,
                mint: mint
            ))
        }

        // 4. SPL token transfer
        instructions.append(TokenProgram.transfer(
            source: senderATA,
            destination: recipientATA,
            owner: signer.publicKey,
            amount: amount
        ))

        // 5. Jito tip
        if tipLamports > 0 {
            instructions.append(try JitoTip.tipInstruction(from: signer.publicKey, lamports: tipLamports))
        }

        // Build message and transaction
        let message = try Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: instructions
        )

        var transaction = Transaction(message: message)
        try await transaction.sign(with: signer)

        // Calculate fees
        let baseFee: UInt64 = 5000
        let (rawProduct, overflow) = UInt64(computeUnitLimit).multipliedReportingOverflow(by: priorityFee)
        let priorityFeeTotal = overflow ? UInt64.max / 1_000_000 : rawProduct / 1_000_000
        let fees = TransactionFees(
            baseFee: baseFee,
            priorityFee: priorityFeeTotal,
            tipAmount: tipLamports
        )

        return (transaction, fees)
    }

    /// Build and sign a Send NFT transaction (SPL token transfer with amount=1, decimals=0).
    /// Creates the recipient's associated token account if it doesn't exist.
    public func buildSendNFT(
        from signer: TransactionSigner,
        to recipient: SolanaPublicKey,
        mint: SolanaPublicKey,
        computeUnitLimit: UInt32 = 200_000,
        computeUnitPrice: UInt64? = nil,
        tipLamports: UInt64 = JitoTip.defaultTipLamports
    ) async throws -> (transaction: Transaction, fees: TransactionFees) {
        return try await buildSendToken(
            from: signer,
            to: recipient,
            mint: mint,
            amount: 1,
            decimals: 0,
            computeUnitLimit: computeUnitLimit,
            computeUnitPrice: computeUnitPrice,
            tipLamports: tipLamports
        )
    }

    /// Submit a signed transaction via Jito for MEV protection.
    public func submitViaJito(transaction: Transaction) async throws -> String {
        let serialized = transaction.serialize()
        return try await jitoClient.sendTransaction(serializedTransaction: serialized)
    }

    /// Submit a signed transaction via standard RPC (fallback).
    public func submitViaRPC(transaction: Transaction) async throws -> String {
        let base64 = transaction.serializeBase64()
        return try await rpcClient.sendTransaction(encodedTransaction: base64)
    }

    // MARK: - Jupiter Swap

    /// Build a signed v0 swap transaction using Jupiter swap instructions.
    ///
    /// Flow:
    /// 1. Fetch swap instructions from Jupiter for the given quote
    /// 2. Decode all instructions from Jupiter response
    /// 3. Fetch Address Lookup Tables referenced by the swap
    /// 4. Build a V0Message with compute budget + setup + swap + cleanup + Jito tip
    /// 5. Sign and return the versioned transaction
    ///
    /// - Parameters:
    ///   - quote: The Jupiter quote to execute
    ///   - userPublicKey: The user's wallet public key (base58)
    ///   - signer: The transaction signer
    ///   - tipLamports: Jito tip amount in lamports
    /// - Returns: A signed VersionedTransaction and fee breakdown
    public func buildSwap(
        quote: JupiterQuote,
        userPublicKey: String,
        signer: TransactionSigner,
        tipLamports: UInt64 = JitoTip.defaultTipLamports
    ) async throws -> (transaction: VersionedTransaction, fees: TransactionFees) {
        // 1. Get swap instructions from Jupiter
        let swapInstructions = try await jupiterClient.getSwapInstructions(
            quote: quote,
            userPublicKey: userPublicKey
        )

        // 2. Decode all instructions
        var instructions: [Instruction] = []

        // Compute budget instructions from Jupiter
        let computeBudgetIxs = try InstructionDecoder.decodeAll(swapInstructions.computeBudgetInstructions)
        instructions.append(contentsOf: computeBudgetIxs)

        // Setup instructions
        let setupIxs = try InstructionDecoder.decodeAll(swapInstructions.setupInstructions)
        instructions.append(contentsOf: setupIxs)

        // Token ledger instruction (if present)
        if let tokenLedger = swapInstructions.tokenLedgerInstruction {
            instructions.append(try InstructionDecoder.decode(tokenLedger))
        }

        // Main swap instruction
        instructions.append(try InstructionDecoder.decode(swapInstructions.swapInstruction))

        // Cleanup instruction (if present)
        if let cleanup = swapInstructions.cleanupInstruction {
            instructions.append(try InstructionDecoder.decode(cleanup))
        }

        // Jito tip instruction
        if tipLamports > 0 {
            instructions.append(try JitoTip.tipInstruction(from: signer.publicKey, lamports: tipLamports))
        }

        // 3. Fetch Address Lookup Tables
        var addressLookupTables: [AddressLookupTable] = []
        for altAddress in swapInstructions.addressLookupTableAddresses {
            let alt = try await rpcClient.getAddressLookupTable(address: altAddress)
            addressLookupTables.append(alt)
        }

        // 4. Get recent blockhash
        let blockhash = try await rpcClient.getLatestBlockhash()

        // 5. Build V0 message
        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: instructions,
            addressLookupTables: addressLookupTables
        )

        // 6. Sign
        var transaction = VersionedTransaction(message: .v0(v0Message))
        try await transaction.sign(with: signer)

        // Calculate fees (estimate from compute budget instructions if present)
        let baseFee: UInt64 = 5000
        let fees = TransactionFees(
            baseFee: baseFee,
            priorityFee: 0, // Jupiter handles compute budget
            tipAmount: tipLamports
        )

        return (transaction, fees)
    }

    /// Submit a swap transaction via Jito bundle for MEV protection.
    ///
    /// Serializes the transaction to base58 (Jito uses base58, not base64)
    /// and submits it as a bundle.
    ///
    /// - Parameter transaction: The signed versioned transaction
    /// - Returns: The Jito bundle ID
    public func submitSwapViaJito(transaction: VersionedTransaction) async throws -> String {
        let serialized = transaction.serialize()
        return try await jitoClient.sendBundle(serializedTransactions: [serialized])
    }

    // MARK: - Sanctum Liquid Staking

    /// Build a Jito bundle for liquid staking via Sanctum: stake transaction + tip transaction.
    ///
    /// Flow:
    /// 1. Get a swap quote from Sanctum
    /// 2. Get the swap transaction (pre-built, base64-encoded)
    /// 3. Deserialize the transaction
    /// 4. Re-sign with our signer
    /// 5. Build a separate Jito tip transaction
    /// 6. Return both transactions for bundle submission
    ///
    /// - Parameters:
    ///   - signer: The transaction signer
    ///   - outputLstMint: The LST mint to stake into (e.g. JitoSOL, mSOL)
    ///   - amount: Amount of SOL to stake in lamports
    ///   - tipLamports: Jito tip amount in lamports
    /// - Returns: The serialized transactions for the Jito bundle and fee breakdown
    public func buildStake(
        signer: TransactionSigner,
        outputLstMint: String,
        amount: UInt64,
        tipLamports: UInt64 = JitoTip.defaultTipLamports
    ) async throws -> (stakeTransaction: VersionedTransaction, tipTransaction: Transaction, fees: TransactionFees) {
        // 1. Get quote from Sanctum
        let quote = try await sanctumClient.getQuote(
            outputLstMint: outputLstMint,
            amount: amount
        )

        // 2. Get swap transaction from Sanctum
        let swapResponse = try await sanctumClient.swap(
            outputLstMint: outputLstMint,
            amount: amount,
            quotedAmount: quote.outAmount,
            signer: signer.publicKey.base58
        )

        // 3. Deserialize the base64 transaction
        guard let txData = Data(base64Encoded: swapResponse.tx) else {
            throw SolanaError.decodingError("Invalid base64 in Sanctum swap response")
        }
        var stakeTx = try VersionedTransaction.deserialize(from: txData)

        // 3a. Verify fee payer matches our signer (prevent malicious pre-built tx)
        let feePayer: SolanaPublicKey
        switch stakeTx.message {
        case .legacy(let msg): feePayer = msg.accountKeys[0]
        case .v0(let msg): feePayer = msg.accountKeys[0]
        }
        guard feePayer == signer.publicKey else {
            throw SolanaError.decodingError("Sanctum transaction fee payer (\(feePayer.base58.prefix(8))...) does not match wallet (\(signer.publicKey.base58.prefix(8))...)")
        }

        // 4. Re-sign with our signer
        try await stakeTx.sign(with: signer)

        // 5. Build a separate tip transaction
        let blockhash = try await rpcClient.getLatestBlockhash()

        var tipInstructions: [Instruction] = []
        tipInstructions.append(ComputeBudgetProgram.setComputeUnitLimit(200_000))
        tipInstructions.append(ComputeBudgetProgram.setComputeUnitPrice(1000))

        if tipLamports > 0 {
            tipInstructions.append(try JitoTip.tipInstruction(from: signer.publicKey, lamports: tipLamports))
        }

        let tipMessage = try Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: tipInstructions
        )

        var tipTx = Transaction(message: tipMessage)
        try await tipTx.sign(with: signer)

        // Calculate fees
        let baseFee: UInt64 = 5000 * 2 // Two transactions, each with a signature
        let fees = TransactionFees(
            baseFee: baseFee,
            priorityFee: 0, // Sanctum handles compute budget for stake tx
            tipAmount: tipLamports
        )

        return (stakeTx, tipTx, fees)
    }

    /// Submit a stake + tip bundle via Jito for MEV protection.
    ///
    /// - Parameters:
    ///   - stakeTransaction: The signed Sanctum stake transaction
    ///   - tipTransaction: The signed Jito tip transaction
    /// - Returns: The Jito bundle ID
    public func submitStakeViaJito(
        stakeTransaction: VersionedTransaction,
        tipTransaction: Transaction
    ) async throws -> String {
        let serializedStake = stakeTransaction.serialize()
        let serializedTip = tipTransaction.serialize()
        return try await jitoClient.sendBundle(serializedTransactions: [serializedStake, serializedTip])
    }
}

/// Fee breakdown for a transaction.
public struct TransactionFees: Sendable {
    public let baseFee: UInt64       // Per-signature fee (5000 lamports)
    public let priorityFee: UInt64   // Compute budget priority fee
    public let tipAmount: UInt64     // Jito tip

    public init(baseFee: UInt64, priorityFee: UInt64, tipAmount: UInt64) {
        self.baseFee = baseFee
        self.priorityFee = priorityFee
        self.tipAmount = tipAmount
    }

    public var totalFee: UInt64 { baseFee + priorityFee + tipAmount }

    /// Total fee as SOL
    public var totalSOL: Double {
        Double(totalFee) / 1_000_000_000.0
    }
}

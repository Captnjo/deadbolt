import Foundation

/// Analyzes a list of Solana instructions to compute balance changes, fee breakdowns,
/// and action descriptions without making any RPC calls.
public enum InstructionAnalyzer {

    // MARK: - Known Program IDs

    /// Set of known/recognized program IDs for warning detection.
    public static let knownProgramIds: Set<String> = {
        var ids = Set<String>()
        ids.insert(SystemProgram.programId.base58)
        ids.insert(TokenProgram.programId.base58)
        ids.insert(TokenProgram.associatedTokenProgramId.base58)
        ids.insert(ComputeBudgetProgram.programId.base58)
        // Jupiter v6 program
        ids.insert("JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4")
        // Sanctum router
        ids.insert("stkitrT1Uoy18Dk1fTrgPw8W6MVzoCfYoAFT4MLsmhq")
        return ids
    }()

    /// Set of known Jito tip account addresses.
    public static let jitoTipAccounts: Set<String> = Set(JitoTip.tipAccounts)

    // MARK: - Analysis Result

    /// The result of analyzing a set of instructions.
    public struct AnalysisResult: Sendable {
        /// Human-readable action description.
        public let actionDescription: String
        /// SOL balance changes per account (in lamports, signed).
        public let solChanges: [String: Int64]
        /// Token balance changes per account per mint.
        public let tokenChanges: [String: [(mint: String, amount: Int64)]]
        /// Fee breakdown.
        public let fees: TransactionFees
        /// List of unrecognized program IDs.
        public let unrecognizedPrograms: [String]
        /// Whether a Jito tip was detected.
        public let hasJitoTip: Bool
        /// The Jito tip amount in lamports (0 if no tip).
        public let jitoTipLamports: UInt64
    }

    // MARK: - Parsed Instruction Types

    private enum ParsedInstruction {
        case systemTransfer(from: String, to: String, lamports: UInt64)
        case splTokenTransfer(source: String, destination: String, owner: String, amount: UInt64)
        case computeUnitLimit(units: UInt32)
        case computeUnitPrice(microLamports: UInt64)
        case jitoTip(from: String, to: String, lamports: UInt64)
        case unrecognized(programId: String)
    }

    // MARK: - Public API

    /// Analyze a list of instructions and return structured balance changes and fee info.
    public static func analyze(instructions: [Instruction]) -> AnalysisResult {
        var parsed: [ParsedInstruction] = []

        for instruction in instructions {
            parsed.append(parseInstruction(instruction))
        }

        return buildResult(from: parsed)
    }

    // MARK: - Instruction Parsing

    private static func parseInstruction(_ instruction: Instruction) -> ParsedInstruction {
        let programId = instruction.programId.base58

        // SystemProgram
        if programId == SystemProgram.programId.base58 {
            return parseSystemInstruction(instruction)
        }

        // Token Program
        if programId == TokenProgram.programId.base58 {
            return parseTokenInstruction(instruction)
        }

        // Compute Budget Program
        if programId == ComputeBudgetProgram.programId.base58 {
            return parseComputeBudgetInstruction(instruction)
        }

        // Check if this is a known program
        if knownProgramIds.contains(programId) {
            // Known but not specifically parsed — not unrecognized
            return .unrecognized(programId: programId)
        }

        return .unrecognized(programId: programId)
    }

    private static func parseSystemInstruction(_ instruction: Instruction) -> ParsedInstruction {
        let data = instruction.data
        // SystemProgram.transfer: 4 bytes u32 LE (value 2) + 8 bytes u64 LE lamports = 12 bytes
        guard data.count >= 12 else {
            return .unrecognized(programId: SystemProgram.programId.base58)
        }

        let instructionIndex = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        guard instructionIndex == 2 else {
            return .unrecognized(programId: SystemProgram.programId.base58)
        }

        let lamports = readUInt64LE(data, offset: 4)

        guard instruction.accounts.count >= 2 else {
            return .unrecognized(programId: SystemProgram.programId.base58)
        }

        let from = instruction.accounts[0].publicKey.base58
        let to = instruction.accounts[1].publicKey.base58

        // Check if this is a Jito tip
        if jitoTipAccounts.contains(to) {
            return .jitoTip(from: from, to: to, lamports: lamports)
        }

        return .systemTransfer(from: from, to: to, lamports: lamports)
    }

    private static func parseTokenInstruction(_ instruction: Instruction) -> ParsedInstruction {
        let data = instruction.data
        // SPL Token transfer: 1 byte (value 3) + 8 bytes u64 LE amount = 9 bytes
        guard data.count >= 9, data[0] == 3 else {
            return .unrecognized(programId: TokenProgram.programId.base58)
        }

        let amount = readUInt64LE(data, offset: 1)

        guard instruction.accounts.count >= 3 else {
            return .unrecognized(programId: TokenProgram.programId.base58)
        }

        let source = instruction.accounts[0].publicKey.base58
        let destination = instruction.accounts[1].publicKey.base58
        let owner = instruction.accounts[2].publicKey.base58

        return .splTokenTransfer(source: source, destination: destination, owner: owner, amount: amount)
    }

    private static func parseComputeBudgetInstruction(_ instruction: Instruction) -> ParsedInstruction {
        let data = instruction.data
        guard !data.isEmpty else {
            return .unrecognized(programId: ComputeBudgetProgram.programId.base58)
        }

        switch data[0] {
        case 2:
            // SetComputeUnitLimit: 1 byte + 4 bytes u32 LE
            guard data.count >= 5 else {
                return .unrecognized(programId: ComputeBudgetProgram.programId.base58)
            }
            let units = readUInt32LE(data, offset: 1)
            return .computeUnitLimit(units: units)

        case 3:
            // SetComputeUnitPrice: 1 byte + 8 bytes u64 LE
            guard data.count >= 9 else {
                return .unrecognized(programId: ComputeBudgetProgram.programId.base58)
            }
            let microLamports = readUInt64LE(data, offset: 1)
            return .computeUnitPrice(microLamports: microLamports)

        default:
            return .unrecognized(programId: ComputeBudgetProgram.programId.base58)
        }
    }

    // MARK: - Result Building

    private static func buildResult(from parsed: [ParsedInstruction]) -> AnalysisResult {
        var solChanges: [String: Int64] = [:]
        var tokenChanges: [String: [(mint: String, amount: Int64)]] = [:]
        var unrecognizedPrograms: [String] = []
        var computeUnitLimit: UInt32 = 200_000 // default
        var computeUnitPrice: UInt64 = 0
        var hasJitoTip = false
        var jitoTipLamports: UInt64 = 0
        var descriptions: [String] = []
        var totalSystemTransferLamports: UInt64 = 0
        var transferRecipient: String?

        for item in parsed {
            switch item {
            case .systemTransfer(let from, let to, let lamports):
                solChanges[from, default: 0] -= Int64(lamports)
                solChanges[to, default: 0] += Int64(lamports)
                totalSystemTransferLamports += lamports
                transferRecipient = to
                let solAmount = String(format: "%.9g", Double(lamports) / 1_000_000_000.0)
                descriptions.append("Send \(solAmount) SOL to \(shortAddress(to))")

            case .splTokenTransfer(let source, let destination, _, let amount):
                // For token transfers, we track by token account address
                // The mint is not directly available from the instruction — use "unknown" placeholder
                tokenChanges[source, default: []].append((mint: "unknown", amount: -Int64(amount)))
                tokenChanges[destination, default: []].append((mint: "unknown", amount: Int64(amount)))
                descriptions.append("Transfer \(amount) tokens to \(shortAddress(destination))")

            case .computeUnitLimit(let units):
                computeUnitLimit = units

            case .computeUnitPrice(let microLamports):
                computeUnitPrice = microLamports

            case .jitoTip(let from, _, let lamports):
                hasJitoTip = true
                jitoTipLamports = lamports
                solChanges[from, default: 0] -= Int64(lamports)

            case .unrecognized(let programId):
                if !knownProgramIds.contains(programId) {
                    unrecognizedPrograms.append(programId)
                }
            }
        }

        // Calculate priority fee
        let priorityFeeTotal = UInt64(computeUnitLimit) * computeUnitPrice / 1_000_000
        let baseFee: UInt64 = 5000

        let fees = TransactionFees(
            baseFee: baseFee,
            priorityFee: priorityFeeTotal,
            tipAmount: jitoTipLamports
        )

        // Build action description
        let actionDescription: String
        if descriptions.isEmpty {
            actionDescription = "Unknown transaction"
        } else if descriptions.count == 1 {
            actionDescription = descriptions[0]
        } else {
            // Filter out redundant compute budget descriptions
            let meaningful = descriptions.filter { !$0.isEmpty }
            actionDescription = meaningful.joined(separator: "; ")
        }

        return AnalysisResult(
            actionDescription: actionDescription,
            solChanges: solChanges,
            tokenChanges: tokenChanges,
            fees: fees,
            unrecognizedPrograms: unrecognizedPrograms,
            hasJitoTip: hasJitoTip,
            jitoTipLamports: jitoTipLamports
        )
    }

    // MARK: - Helpers

    /// Read a UInt64 from Data in little-endian byte order (alignment-safe).
    private static func readUInt64LE(_ data: Data, offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(data[offset + i]) << (i * 8)
        }
        return value
    }

    /// Read a UInt32 from Data in little-endian byte order (alignment-safe).
    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(data[offset + i]) << (i * 8)
        }
        return value
    }

    private static func shortAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        let start = address.prefix(4)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
}

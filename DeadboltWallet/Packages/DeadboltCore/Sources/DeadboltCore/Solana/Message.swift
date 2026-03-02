import Foundation

/// Solana legacy transaction message (v0 legacy format).
/// Layout: header (3 bytes) + account keys + recent blockhash + instructions
public struct Message: Sendable {
    public let header: MessageHeader
    public let accountKeys: [SolanaPublicKey]
    public let recentBlockhash: Data // 32 bytes
    public let instructions: [CompiledInstruction]

    /// Build a Message from high-level instructions, automatically computing the header,
    /// deduplicating + ordering account keys, and compiling instruction indices.
    public init(
        feePayer: SolanaPublicKey,
        recentBlockhash: String,
        instructions: [Instruction]
    ) throws {
        let blockhashData = try Base58.decode(recentBlockhash)
        guard blockhashData.count == 32 else {
            throw SolanaError.decodingError("Invalid blockhash length: \(blockhashData.count)")
        }

        // Collect all unique accounts with their highest privilege level
        var accountMap: [SolanaPublicKey: (isSigner: Bool, isWritable: Bool)] = [:]

        // Fee payer is always signer + writable
        accountMap[feePayer] = (isSigner: true, isWritable: true)

        // Collect from instructions
        for ix in instructions {
            // Program ID is read-only, non-signer
            let existing = accountMap[ix.programId]
            accountMap[ix.programId] = (
                isSigner: existing?.isSigner ?? false,
                isWritable: existing?.isWritable ?? false
            )

            for acct in ix.accounts {
                let existing = accountMap[acct.publicKey]
                accountMap[acct.publicKey] = (
                    isSigner: (existing?.isSigner ?? false) || acct.isSigner,
                    isWritable: (existing?.isWritable ?? false) || acct.isWritable
                )
            }
        }

        // Sort accounts: signers+writable first, then signers+readonly, then non-signers+writable, then non-signers+readonly.
        // Fee payer is always first.
        var signerWritable: [SolanaPublicKey] = []
        var signerReadonly: [SolanaPublicKey] = []
        var nonSignerWritable: [SolanaPublicKey] = []
        var nonSignerReadonly: [SolanaPublicKey] = []

        for (key, meta) in accountMap {
            if key == feePayer { continue } // handled separately
            switch (meta.isSigner, meta.isWritable) {
            case (true, true):   signerWritable.append(key)
            case (true, false):  signerReadonly.append(key)
            case (false, true):  nonSignerWritable.append(key)
            case (false, false): nonSignerReadonly.append(key)
            }
        }

        // Sort each group by public key bytes to match web3.js ordering
        signerWritable.sort { $0.data.lexicographicallyPrecedes($1.data) }
        signerReadonly.sort { $0.data.lexicographicallyPrecedes($1.data) }
        nonSignerWritable.sort { $0.data.lexicographicallyPrecedes($1.data) }
        nonSignerReadonly.sort { $0.data.lexicographicallyPrecedes($1.data) }

        let orderedKeys = [feePayer] + signerWritable + signerReadonly + nonSignerWritable + nonSignerReadonly

        let numRequiredSignatures = 1 + signerWritable.count + signerReadonly.count
        let numReadonlySignedAccounts = signerReadonly.count
        let numReadonlyUnsignedAccounts = nonSignerReadonly.count

        // Build account index lookup
        var keyIndex: [SolanaPublicKey: UInt8] = [:]
        for (i, key) in orderedKeys.enumerated() {
            keyIndex[key] = UInt8(i)
        }

        // Compile instructions
        var compiled: [CompiledInstruction] = []
        for ix in instructions {
            guard let programIdIndex = keyIndex[ix.programId] else {
                throw SolanaError.decodingError("Program ID not found in account keys")
            }
            let accountIndices = try ix.accounts.map { acct -> UInt8 in
                guard let idx = keyIndex[acct.publicKey] else {
                    throw SolanaError.decodingError("Account not found in account keys: \(acct.publicKey)")
                }
                return idx
            }
            compiled.append(CompiledInstruction(
                programIdIndex: programIdIndex,
                accountIndices: accountIndices,
                data: ix.data
            ))
        }

        self.header = MessageHeader(
            numRequiredSignatures: UInt8(numRequiredSignatures),
            numReadonlySignedAccounts: UInt8(numReadonlySignedAccounts),
            numReadonlyUnsignedAccounts: UInt8(numReadonlyUnsignedAccounts)
        )
        self.accountKeys = orderedKeys
        self.recentBlockhash = blockhashData
        self.instructions = compiled
    }

    /// Deserialize a legacy message from its wire format bytes.
    ///
    /// Wire format:
    /// - 3 bytes: header (numRequiredSignatures, numReadonlySignedAccounts, numReadonlyUnsignedAccounts)
    /// - compact-u16: account key count + 32 bytes per key
    /// - 32 bytes: recent blockhash
    /// - compact-u16: instruction count + compiled instructions
    public init(deserializing data: Data, offset: inout Int) throws {
        guard offset + 3 <= data.count else {
            throw SolanaError.decodingError("Not enough bytes for legacy message header")
        }

        // Header: 3 bytes
        self.header = MessageHeader(
            numRequiredSignatures: data[offset],
            numReadonlySignedAccounts: data[offset + 1],
            numReadonlyUnsignedAccounts: data[offset + 2]
        )
        offset += 3

        // Account keys
        let (keyCount, keyCountBytes) = try CompactU16.decode(data, offset: offset)
        offset += keyCountBytes

        var keys: [SolanaPublicKey] = []
        for _ in 0..<keyCount {
            guard offset + 32 <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for account key")
            }
            keys.append(try SolanaPublicKey(data: data[offset..<offset + 32]))
            offset += 32
        }
        self.accountKeys = keys

        // Recent blockhash: 32 bytes
        guard offset + 32 <= data.count else {
            throw SolanaError.decodingError("Not enough bytes for blockhash")
        }
        self.recentBlockhash = Data(data[offset..<offset + 32])
        offset += 32

        // Instructions
        let (ixCount, ixCountBytes) = try CompactU16.decode(data, offset: offset)
        offset += ixCountBytes

        var ixs: [CompiledInstruction] = []
        for _ in 0..<ixCount {
            guard offset < data.count else {
                throw SolanaError.decodingError("Not enough bytes for instruction programIdIndex")
            }
            let programIdIndex = data[offset]
            offset += 1

            let (acctCount, acctCountBytes) = try CompactU16.decode(data, offset: offset)
            offset += acctCountBytes

            guard offset + Int(acctCount) <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for instruction account indices")
            }
            let accountIndices = Array(data[offset..<offset + Int(acctCount)])
            offset += Int(acctCount)

            let (dataLen, dataLenBytes) = try CompactU16.decode(data, offset: offset)
            offset += dataLenBytes

            guard offset + Int(dataLen) <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for instruction data")
            }
            let ixData = Data(data[offset..<offset + Int(dataLen)])
            offset += Int(dataLen)

            ixs.append(CompiledInstruction(
                programIdIndex: programIdIndex,
                accountIndices: accountIndices,
                data: ixData
            ))
        }
        self.instructions = ixs
    }

    /// Serialize the message to its wire format bytes.
    public func serialize() -> Data {
        var data = Data()

        // Header: 3 bytes
        data.append(header.numRequiredSignatures)
        data.append(header.numReadonlySignedAccounts)
        data.append(header.numReadonlyUnsignedAccounts)

        // Account keys: compact-u16 length + 32 bytes each
        data.append(contentsOf: CompactU16.encode(UInt16(accountKeys.count)))
        for key in accountKeys {
            data.append(key.data)
        }

        // Recent blockhash: 32 bytes
        data.append(recentBlockhash)

        // Instructions: compact-u16 length + each instruction
        data.append(contentsOf: CompactU16.encode(UInt16(instructions.count)))
        for ix in instructions {
            data.append(ix.programIdIndex)
            data.append(contentsOf: CompactU16.encode(UInt16(ix.accountIndices.count)))
            for idx in ix.accountIndices {
                data.append(idx)
            }
            data.append(contentsOf: CompactU16.encode(UInt16(ix.data.count)))
            data.append(ix.data)
        }

        return data
    }
}

public struct MessageHeader: Sendable {
    public let numRequiredSignatures: UInt8
    public let numReadonlySignedAccounts: UInt8
    public let numReadonlyUnsignedAccounts: UInt8
}

/// A compiled instruction with account indices instead of full public keys.
public struct CompiledInstruction: Sendable {
    public let programIdIndex: UInt8
    public let accountIndices: [UInt8]
    public let data: Data
}

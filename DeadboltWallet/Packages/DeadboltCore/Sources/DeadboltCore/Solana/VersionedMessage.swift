import Foundation

/// A Solana transaction message that can be either legacy or v0 format.
public enum VersionedMessage: Sendable {
    case legacy(Message)
    case v0(V0Message)

    /// Deserialize a versioned message from its wire format bytes.
    /// Detects whether the message is legacy or v0 by checking bit 7 of the first byte.
    public static func deserialize(from data: Data, offset: inout Int) throws -> VersionedMessage {
        guard offset < data.count else {
            throw SolanaError.decodingError("No bytes available for message deserialization")
        }

        let firstByte = data[offset]

        if firstByte & 0x80 != 0 {
            // V0 message: consume the 0x80 prefix byte
            offset += 1
            let v0Message = try V0Message(deserializing: data, offset: &offset)
            return .v0(v0Message)
        } else {
            // Legacy message: first byte is numRequiredSignatures (header start)
            let message = try Message(deserializing: data, offset: &offset)
            return .legacy(message)
        }
    }

    /// Serialize the message to its wire format bytes.
    public func serialize() -> Data {
        switch self {
        case .legacy(let message):
            return message.serialize()
        case .v0(let message):
            return message.serialize()
        }
    }
}

/// Solana v0 transaction message with address lookup table support.
///
/// Wire format:
/// - 1 byte: 0x80 (version prefix for v0)
/// - 3 bytes: header (numRequiredSignatures, numReadonlySignedAccounts, numReadonlyUnsignedAccounts)
/// - compact-u16: static account key count + 32 bytes per key
/// - 32 bytes: recent blockhash
/// - compact-u16: instruction count + compiled instructions
/// - compact-u16: address table lookup count + lookup entries
public struct V0Message: Sendable {
    public let header: MessageHeader
    public let accountKeys: [SolanaPublicKey]
    public let recentBlockhash: Data // 32 bytes
    public let instructions: [CompiledInstruction]
    public let addressTableLookups: [MessageAddressTableLookup]

    public init(
        header: MessageHeader,
        accountKeys: [SolanaPublicKey],
        recentBlockhash: Data,
        instructions: [CompiledInstruction],
        addressTableLookups: [MessageAddressTableLookup]
    ) {
        self.header = header
        self.accountKeys = accountKeys
        self.recentBlockhash = recentBlockhash
        self.instructions = instructions
        self.addressTableLookups = addressTableLookups
    }

    /// Build a V0Message from high-level instructions and resolved address lookup tables.
    ///
    /// This compiles instructions into their compact form, deduplicating accounts and
    /// placing ALT-resolved accounts into the lookup table section of the message.
    public init(
        feePayer: SolanaPublicKey,
        recentBlockhash: String,
        instructions: [Instruction],
        addressLookupTables: [AddressLookupTable]
    ) throws {
        let blockhashData = try Base58.decode(recentBlockhash)
        guard blockhashData.count == 32 else {
            throw SolanaError.decodingError("Invalid blockhash length: \(blockhashData.count)")
        }

        // Build a lookup from ALT address -> (tableIndex, addressIndex) for quick resolution
        var altLookup: [SolanaPublicKey: (tableIndex: Int, addressIndex: Int)] = [:]
        for (tableIdx, table) in addressLookupTables.enumerated() {
            for (addrIdx, addr) in table.addresses.enumerated() {
                // First occurrence wins — if the same key appears in multiple ALTs
                if altLookup[addr] == nil {
                    altLookup[addr] = (tableIndex: tableIdx, addressIndex: addrIdx)
                }
            }
        }

        // Collect all unique accounts with their highest privilege level
        var accountMap: [SolanaPublicKey: (isSigner: Bool, isWritable: Bool)] = [:]

        // Fee payer is always signer + writable
        accountMap[feePayer] = (isSigner: true, isWritable: true)

        for ix in instructions {
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

        // Partition accounts into static keys (must be in the message) vs ALT-resolvable.
        // Accounts that are signers, fee payer, or program IDs MUST be static.
        var staticKeys: [SolanaPublicKey] = []
        var altResolvableWritable: [SolanaPublicKey: (tableIndex: Int, addressIndex: Int)] = [:]
        var altResolvableReadonly: [SolanaPublicKey: (tableIndex: Int, addressIndex: Int)] = [:]

        // Gather all program IDs (these must always be static)
        var programIds = Set<SolanaPublicKey>()
        for ix in instructions {
            programIds.insert(ix.programId)
        }

        for (key, meta) in accountMap {
            let mustBeStatic = meta.isSigner || programIds.contains(key) || key == feePayer
            if mustBeStatic {
                if key != feePayer { // fee payer handled separately
                    staticKeys.append(key)
                }
            } else if let altEntry = altLookup[key] {
                // Can resolve via ALT
                if meta.isWritable {
                    altResolvableWritable[key] = altEntry
                } else {
                    altResolvableReadonly[key] = altEntry
                }
            } else {
                // Not in any ALT, must be static
                staticKeys.append(key)
            }
        }

        // Sort static keys into categories (same ordering as legacy Message)
        var signerWritable: [SolanaPublicKey] = []
        var signerReadonly: [SolanaPublicKey] = []
        var nonSignerWritable: [SolanaPublicKey] = []
        var nonSignerReadonly: [SolanaPublicKey] = []

        for key in staticKeys {
            let meta = accountMap[key]!
            switch (meta.isSigner, meta.isWritable) {
            case (true, true):   signerWritable.append(key)
            case (true, false):  signerReadonly.append(key)
            case (false, true):  nonSignerWritable.append(key)
            case (false, false): nonSignerReadonly.append(key)
            }
        }

        signerWritable.sort { $0.data.lexicographicallyPrecedes($1.data) }
        signerReadonly.sort { $0.data.lexicographicallyPrecedes($1.data) }
        nonSignerWritable.sort { $0.data.lexicographicallyPrecedes($1.data) }
        nonSignerReadonly.sort { $0.data.lexicographicallyPrecedes($1.data) }

        let orderedStaticKeys = [feePayer] + signerWritable + signerReadonly + nonSignerWritable + nonSignerReadonly
        let numStaticKeys = orderedStaticKeys.count

        // Build account index lookup: static keys get indices 0..<numStaticKeys
        var keyIndex: [SolanaPublicKey: UInt8] = [:]
        for (i, key) in orderedStaticKeys.enumerated() {
            keyIndex[key] = UInt8(i)
        }

        // ALT-resolved accounts get indices starting after static keys.
        // Build the address table lookup entries for the message.
        // Group by table, then writable indexes first, then readonly indexes.
        struct ALTBuildEntry {
            var writableIndexes: [UInt8] = []
            var readonlyIndexes: [UInt8] = []
            var writableKeys: [SolanaPublicKey] = []
            var readonlyKeys: [SolanaPublicKey] = []
        }

        var altBuildMap: [Int: ALTBuildEntry] = [:]

        for (key, entry) in altResolvableWritable {
            var build = altBuildMap[entry.tableIndex] ?? ALTBuildEntry()
            build.writableIndexes.append(UInt8(entry.addressIndex))
            build.writableKeys.append(key)
            altBuildMap[entry.tableIndex] = build
        }

        for (key, entry) in altResolvableReadonly {
            var build = altBuildMap[entry.tableIndex] ?? ALTBuildEntry()
            build.readonlyIndexes.append(UInt8(entry.addressIndex))
            build.readonlyKeys.append(key)
            altBuildMap[entry.tableIndex] = build
        }

        // Assign indices to ALT-resolved accounts in a deterministic order
        // Sort ALT entries by table index, then within each table by address index
        var nextIndex = UInt8(numStaticKeys)
        var lookups: [MessageAddressTableLookup] = []

        for tableIdx in altBuildMap.keys.sorted() {
            let build = altBuildMap[tableIdx]!
            let table = addressLookupTables[tableIdx]

            // Sort writable by their index in the ALT for determinism
            let sortedWritable = zip(build.writableKeys, build.writableIndexes)
                .sorted { $0.1 < $1.1 }
            let sortedReadonly = zip(build.readonlyKeys, build.readonlyIndexes)
                .sorted { $0.1 < $1.1 }

            for (key, _) in sortedWritable {
                keyIndex[key] = nextIndex
                nextIndex += 1
            }

            for (key, _) in sortedReadonly {
                keyIndex[key] = nextIndex
                nextIndex += 1
            }

            lookups.append(MessageAddressTableLookup(
                accountKey: table.key,
                writableIndexes: sortedWritable.map { UInt8($0.1) },
                readonlyIndexes: sortedReadonly.map { UInt8($0.1) }
            ))
        }

        // Compile instructions using the global key index
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

        let numRequiredSignatures = 1 + signerWritable.count + signerReadonly.count
        let numReadonlySignedAccounts = signerReadonly.count
        let numReadonlyUnsignedAccounts = nonSignerReadonly.count

        self.header = MessageHeader(
            numRequiredSignatures: UInt8(numRequiredSignatures),
            numReadonlySignedAccounts: UInt8(numReadonlySignedAccounts),
            numReadonlyUnsignedAccounts: UInt8(numReadonlyUnsignedAccounts)
        )
        self.accountKeys = orderedStaticKeys
        self.recentBlockhash = blockhashData
        self.instructions = compiled
        self.addressTableLookups = lookups
    }

    /// Deserialize a V0 message from its wire format bytes.
    /// The caller must have already consumed the 0x80 version prefix byte.
    ///
    /// Wire format (after 0x80 prefix):
    /// - 3 bytes: header
    /// - compact-u16: static account key count + 32 bytes per key
    /// - 32 bytes: recent blockhash
    /// - compact-u16: instruction count + compiled instructions
    /// - compact-u16: address table lookup count + lookup entries
    public init(deserializing data: Data, offset: inout Int) throws {
        guard offset + 3 <= data.count else {
            throw SolanaError.decodingError("Not enough bytes for v0 message header")
        }

        // Header: 3 bytes
        self.header = MessageHeader(
            numRequiredSignatures: data[offset],
            numReadonlySignedAccounts: data[offset + 1],
            numReadonlyUnsignedAccounts: data[offset + 2]
        )
        offset += 3

        // Static account keys
        let (keyCount, keyCountBytes) = try CompactU16.decode(data, offset: offset)
        offset += keyCountBytes

        var keys: [SolanaPublicKey] = []
        for _ in 0..<keyCount {
            guard offset + 32 <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for account key in v0 message")
            }
            keys.append(try SolanaPublicKey(data: data[offset..<offset + 32]))
            offset += 32
        }
        self.accountKeys = keys

        // Recent blockhash: 32 bytes
        guard offset + 32 <= data.count else {
            throw SolanaError.decodingError("Not enough bytes for blockhash in v0 message")
        }
        self.recentBlockhash = Data(data[offset..<offset + 32])
        offset += 32

        // Compiled instructions
        let (ixCount, ixCountBytes) = try CompactU16.decode(data, offset: offset)
        offset += ixCountBytes

        var ixs: [CompiledInstruction] = []
        for _ in 0..<ixCount {
            guard offset < data.count else {
                throw SolanaError.decodingError("Not enough bytes for instruction programIdIndex in v0 message")
            }
            let programIdIndex = data[offset]
            offset += 1

            let (acctCount, acctCountBytes) = try CompactU16.decode(data, offset: offset)
            offset += acctCountBytes

            guard offset + Int(acctCount) <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for instruction account indices in v0 message")
            }
            let accountIndices = Array(data[offset..<offset + Int(acctCount)])
            offset += Int(acctCount)

            let (dataLen, dataLenBytes) = try CompactU16.decode(data, offset: offset)
            offset += dataLenBytes

            guard offset + Int(dataLen) <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for instruction data in v0 message")
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

        // Address table lookups
        let (altCount, altCountBytes) = try CompactU16.decode(data, offset: offset)
        offset += altCountBytes

        var lookups: [MessageAddressTableLookup] = []
        for _ in 0..<altCount {
            // Account key: 32 bytes
            guard offset + 32 <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for ALT account key")
            }
            let accountKey = try SolanaPublicKey(data: data[offset..<offset + 32])
            offset += 32

            // Writable indexes
            let (writableCount, writableCountBytes) = try CompactU16.decode(data, offset: offset)
            offset += writableCountBytes

            guard offset + Int(writableCount) <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for ALT writable indexes")
            }
            let writableIndexes = Array(data[offset..<offset + Int(writableCount)])
            offset += Int(writableCount)

            // Readonly indexes
            let (readonlyCount, readonlyCountBytes) = try CompactU16.decode(data, offset: offset)
            offset += readonlyCountBytes

            guard offset + Int(readonlyCount) <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for ALT readonly indexes")
            }
            let readonlyIndexes = Array(data[offset..<offset + Int(readonlyCount)])
            offset += Int(readonlyCount)

            lookups.append(MessageAddressTableLookup(
                accountKey: accountKey,
                writableIndexes: writableIndexes,
                readonlyIndexes: readonlyIndexes
            ))
        }
        self.addressTableLookups = lookups
    }

    /// Serialize the v0 message to its wire format bytes.
    public func serialize() -> Data {
        var data = Data()

        // Version prefix: 0x80 for v0
        data.append(0x80)

        // Header: 3 bytes
        data.append(header.numRequiredSignatures)
        data.append(header.numReadonlySignedAccounts)
        data.append(header.numReadonlyUnsignedAccounts)

        // Static account keys
        data.append(contentsOf: CompactU16.encode(UInt16(accountKeys.count)))
        for key in accountKeys {
            data.append(key.data)
        }

        // Recent blockhash: 32 bytes
        data.append(recentBlockhash)

        // Compiled instructions
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

        // Address table lookups
        data.append(contentsOf: CompactU16.encode(UInt16(addressTableLookups.count)))
        for lookup in addressTableLookups {
            data.append(lookup.accountKey.data) // 32 bytes
            data.append(contentsOf: CompactU16.encode(UInt16(lookup.writableIndexes.count)))
            for idx in lookup.writableIndexes {
                data.append(idx)
            }
            data.append(contentsOf: CompactU16.encode(UInt16(lookup.readonlyIndexes.count)))
            for idx in lookup.readonlyIndexes {
                data.append(idx)
            }
        }

        return data
    }
}

/// An address table lookup entry in a v0 message.
public struct MessageAddressTableLookup: Sendable {
    public let accountKey: SolanaPublicKey
    public let writableIndexes: [UInt8]
    public let readonlyIndexes: [UInt8]

    public init(accountKey: SolanaPublicKey, writableIndexes: [UInt8], readonlyIndexes: [UInt8]) {
        self.accountKey = accountKey
        self.writableIndexes = writableIndexes
        self.readonlyIndexes = readonlyIndexes
    }
}

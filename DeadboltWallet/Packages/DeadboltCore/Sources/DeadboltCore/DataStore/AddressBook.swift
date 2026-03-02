import Foundation

// MARK: - P8-009: Address Book Data Model + Persistence

public struct AddressBookEntry: Codable, Sendable, Equatable {
    public let address: String
    public var tag: String
    public let dateAdded: Date

    public init(address: String, tag: String, dateAdded: Date = Date()) {
        self.address = address
        self.tag = tag
        self.dateAdded = dateAdded
    }
}

public actor AddressBook {
    private var store: [AddressBookEntry] = []
    private let filePath: String

    /// Initialize with a custom file path (useful for testing).
    public init(filePath: String? = nil) {
        let path = filePath ?? {
            let base = DeadboltDirectories.dataDirectory
            return "\(base)/addressbook.json"
        }()
        self.filePath = path
    }

    // MARK: - Load / Save

    /// Load entries from the JSON file. If the file doesn't exist, starts with an empty list.
    public func load() throws {
        guard FileManager.default.fileExists(atPath: filePath) else {
            store = []
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        store = try decoder.decode([AddressBookEntry].self, from: data)
    }

    /// Save current entries to the JSON file. Creates parent directories if needed.
    public func save() throws {
        let dir = (filePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    // MARK: - CRUD Operations

    /// Return all entries.
    public func entries() -> [AddressBookEntry] {
        store
    }

    /// Add a new entry. Validates the address is a valid Base58 Solana public key.
    public func add(address: String, tag: String) throws {
        // Validate address is a valid Base58 Solana public key (32 bytes)
        let _ = try SolanaPublicKey(base58: address)

        // Check for duplicates
        if store.contains(where: { $0.address == address }) {
            throw SolanaError.invalidAddressBookEntry("Address already exists in address book")
        }

        let entry = AddressBookEntry(address: address, tag: tag)
        store.append(entry)
    }

    /// Remove an entry by address.
    public func remove(address: String) {
        store.removeAll { $0.address == address }
    }

    /// Update the tag for an existing address.
    public func update(address: String, tag: String) throws {
        guard let index = store.firstIndex(where: { $0.address == address }) else {
            throw SolanaError.invalidAddressBookEntry("Address not found in address book")
        }
        store[index].tag = tag
    }

    /// Find entries by tag (case-insensitive substring match).
    public func find(tag: String) -> [AddressBookEntry] {
        let lowered = tag.lowercased()
        return store.filter { $0.tag.lowercased().contains(lowered) }
    }
}

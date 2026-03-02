import XCTest
@testable import DeadboltCore

final class AddressBookTests: XCTestCase {

    // Use a temp directory for each test
    private var tempDir: String!
    private var tempFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "DeadboltCoreTests_AddressBook_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        tempFilePath = tempDir + "/addressbook.json"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // A known valid Solana address (System Program)
    private let validAddress1 = "11111111111111111111111111111111"
    // Token program
    private let validAddress2 = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    // Another valid address
    private let validAddress3 = "So11111111111111111111111111111111111111112"

    // MARK: - Add / Entries

    func testAddAndListEntries() async throws {
        let book = AddressBook(filePath: tempFilePath)

        try await book.add(address: validAddress1, tag: "System Program")
        try await book.add(address: validAddress2, tag: "Token Program")

        let entries = await book.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].address, validAddress1)
        XCTAssertEqual(entries[0].tag, "System Program")
        XCTAssertEqual(entries[1].address, validAddress2)
        XCTAssertEqual(entries[1].tag, "Token Program")
    }

    // MARK: - Remove

    func testRemoveEntry() async throws {
        let book = AddressBook(filePath: tempFilePath)

        try await book.add(address: validAddress1, tag: "System Program")
        try await book.add(address: validAddress2, tag: "Token Program")

        await book.remove(address: validAddress1)

        let entries = await book.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].address, validAddress2)
    }

    // MARK: - Update

    func testUpdateTag() async throws {
        let book = AddressBook(filePath: tempFilePath)

        try await book.add(address: validAddress1, tag: "Old Tag")
        try await book.update(address: validAddress1, tag: "New Tag")

        let entries = await book.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].tag, "New Tag")
    }

    func testUpdateNonexistentAddressThrows() async {
        let book = AddressBook(filePath: tempFilePath)

        do {
            try await book.update(address: validAddress1, tag: "Tag")
            XCTFail("Should have thrown")
        } catch let error as SolanaError {
            if case .invalidAddressBookEntry = error {
                // expected
            } else {
                XCTFail("Expected invalidAddressBookEntry, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Find

    func testFindByTag() async throws {
        let book = AddressBook(filePath: tempFilePath)

        try await book.add(address: validAddress1, tag: "My Wallet")
        try await book.add(address: validAddress2, tag: "Exchange Hot Wallet")
        try await book.add(address: validAddress3, tag: "Friend")

        let results = await book.find(tag: "wallet")
        XCTAssertEqual(results.count, 2, "Case-insensitive search for 'wallet' should find 2 entries")
    }

    // MARK: - Duplicate Detection

    func testAddDuplicateAddressThrows() async throws {
        let book = AddressBook(filePath: tempFilePath)

        try await book.add(address: validAddress1, tag: "First")

        do {
            try await book.add(address: validAddress1, tag: "Second")
            XCTFail("Should have thrown for duplicate address")
        } catch let error as SolanaError {
            if case .invalidAddressBookEntry = error {
                // expected
            } else {
                XCTFail("Expected invalidAddressBookEntry, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Invalid Address Rejection

    func testInvalidAddressRejected() async {
        let book = AddressBook(filePath: tempFilePath)

        do {
            try await book.add(address: "not-a-valid-address!!!", tag: "Bad")
            XCTFail("Should have thrown for invalid address")
        } catch let error as SolanaError {
            if case .invalidAddressBookEntry = error {
                // expected
            } else if case .invalidBase58Character = error {
                // also acceptable — thrown by SolanaPublicKey
            } else {
                XCTFail("Expected invalidAddressBookEntry or invalidBase58Character, got \(error)")
            }
        } catch {
            // SolanaPublicKey might throw its own error type which gets wrapped
        }
    }

    func testTooShortAddressRejected() async {
        let book = AddressBook(filePath: tempFilePath)

        do {
            try await book.add(address: "ABC", tag: "Too Short")
            XCTFail("Should have thrown for address that decodes to wrong length")
        } catch {
            // Expected: either invalidPublicKeyLength or invalidAddressBookEntry
        }
    }

    // MARK: - Persistence (Save then Load)

    func testPersistenceSaveAndLoad() async throws {
        // Save
        let book1 = AddressBook(filePath: tempFilePath)
        try await book1.add(address: validAddress1, tag: "System Program")
        try await book1.add(address: validAddress2, tag: "Token Program")
        try await book1.save()

        // Load in a new instance
        let book2 = AddressBook(filePath: tempFilePath)
        try await book2.load()

        let entries = await book2.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].address, validAddress1)
        XCTAssertEqual(entries[0].tag, "System Program")
        XCTAssertEqual(entries[1].address, validAddress2)
        XCTAssertEqual(entries[1].tag, "Token Program")
    }

    func testLoadNonexistentFileStartsEmpty() async throws {
        let book = AddressBook(filePath: tempDir + "/nonexistent.json")
        try await book.load()

        let entries = await book.entries()
        XCTAssertTrue(entries.isEmpty)
    }
}

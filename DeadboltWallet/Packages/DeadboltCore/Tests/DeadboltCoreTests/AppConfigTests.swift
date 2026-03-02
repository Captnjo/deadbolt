import XCTest
@testable import DeadboltCore

final class AppConfigTests: XCTestCase {

    private var tempDir: String!
    private var tempFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "DeadboltCoreTests_AppConfig_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        tempFilePath = tempDir + "/config.json"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultValues() async {
        let config = AppConfig(filePath: tempFilePath)

        let rpc = await config.rpcURL
        let wallet = await config.activeWalletAddress
        let jito = await config.jitoEnabled

        XCTAssertTrue(rpc.contains("mainnet"), "Expected mainnet RPC URL, got \(rpc)")
        XCTAssertNil(wallet)
        XCTAssertTrue(jito)
    }

    // MARK: - Update Methods

    func testUpdateRpcURL() async {
        let config = AppConfig(filePath: tempFilePath)

        await config.update(rpcURL: "https://devnet.solana.com")
        let rpc = await config.rpcURL
        XCTAssertEqual(rpc, "https://devnet.solana.com")
    }

    func testUpdateActiveWallet() async {
        let config = AppConfig(filePath: tempFilePath)

        await config.update(activeWallet: "11111111111111111111111111111111")
        let wallet = await config.activeWalletAddress
        XCTAssertEqual(wallet, "11111111111111111111111111111111")

        await config.update(activeWallet: nil)
        let walletAfterClear = await config.activeWalletAddress
        XCTAssertNil(walletAfterClear)
    }

    func testUpdateJitoEnabled() async {
        let config = AppConfig(filePath: tempFilePath)

        await config.update(jitoEnabled: false)
        let jito = await config.jitoEnabled
        XCTAssertFalse(jito)
    }

    // MARK: - Persistence

    func testSaveAndLoad() async throws {
        // Configure and save
        let config1 = AppConfig(filePath: tempFilePath)
        await config1.update(rpcURL: "https://custom-rpc.example.com")
        await config1.update(activeWallet: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        await config1.update(jitoEnabled: false)
        try await config1.save()

        // Load in new instance
        let config2 = AppConfig(filePath: tempFilePath)
        try await config2.load()

        let rpc = await config2.rpcURL
        let wallet = await config2.activeWalletAddress
        let jito = await config2.jitoEnabled

        XCTAssertEqual(rpc, "https://custom-rpc.example.com")
        XCTAssertEqual(wallet, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertFalse(jito)
    }

    func testLoadNonexistentFileKeepsDefaults() async throws {
        let config = AppConfig(filePath: tempDir + "/nonexistent.json")
        try await config.load()

        let rpc = await config.rpcURL
        let wallet = await config.activeWalletAddress
        let jito = await config.jitoEnabled

        XCTAssertTrue(rpc.contains("mainnet"), "Expected mainnet RPC URL, got \(rpc)")
        XCTAssertNil(wallet)
        XCTAssertTrue(jito)
    }

    func testSaveCreatesParentDirectories() async throws {
        let nestedPath = tempDir + "/nested/deep/config.json"
        let config = AppConfig(filePath: nestedPath)
        await config.update(rpcURL: "https://test.example.com")
        try await config.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedPath),
            "Config file should be created even with nested directories")
    }
}

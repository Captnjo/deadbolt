import XCTest
@testable import DeadboltCore

final class GuardrailsConfigTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultValues() {
        let config = GuardrailsConfig()

        XCTAssertEqual(config.maxSOLPerTransaction, 10.0)
        XCTAssertEqual(config.maxUSDPerTransaction, 1000.0)
        XCTAssertEqual(config.dailyTransactionLimit, 50)
        XCTAssertEqual(config.dailyUSDLimit, 5000.0)
        XCTAssertTrue(config.whitelistedTokens.isEmpty)
        XCTAssertTrue(config.whitelistedPrograms.isEmpty)
        XCTAssertEqual(config.cooldownSeconds, 5)
    }

    func testCustomValues() {
        let config = GuardrailsConfig(
            maxSOLPerTransaction: 5.0,
            maxUSDPerTransaction: 500.0,
            dailyTransactionLimit: 20,
            dailyUSDLimit: 2000.0,
            whitelistedTokens: ["So11111111111111111111111111111111111111112"],
            whitelistedPrograms: ["11111111111111111111111111111111"],
            cooldownSeconds: 10
        )

        XCTAssertEqual(config.maxSOLPerTransaction, 5.0)
        XCTAssertEqual(config.maxUSDPerTransaction, 500.0)
        XCTAssertEqual(config.dailyTransactionLimit, 20)
        XCTAssertEqual(config.dailyUSDLimit, 2000.0)
        XCTAssertEqual(config.whitelistedTokens.count, 1)
        XCTAssertEqual(config.whitelistedPrograms.count, 1)
        XCTAssertEqual(config.cooldownSeconds, 10)
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let original = GuardrailsConfig(
            maxSOLPerTransaction: 3.5,
            maxUSDPerTransaction: 750.0,
            dailyTransactionLimit: 30,
            dailyUSDLimit: 3000.0,
            whitelistedTokens: ["So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"],
            whitelistedPrograms: GuardrailsConfig.defaultWhitelistedPrograms,
            cooldownSeconds: 15
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GuardrailsConfig.self, from: data)

        XCTAssertEqual(decoded.maxSOLPerTransaction, original.maxSOLPerTransaction)
        XCTAssertEqual(decoded.maxUSDPerTransaction, original.maxUSDPerTransaction)
        XCTAssertEqual(decoded.dailyTransactionLimit, original.dailyTransactionLimit)
        XCTAssertEqual(decoded.dailyUSDLimit, original.dailyUSDLimit)
        XCTAssertEqual(decoded.whitelistedTokens, original.whitelistedTokens)
        XCTAssertEqual(decoded.whitelistedPrograms, original.whitelistedPrograms)
        XCTAssertEqual(decoded.cooldownSeconds, original.cooldownSeconds)
    }

    func testCodableWithEmptyWhitelists() throws {
        let original = GuardrailsConfig()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GuardrailsConfig.self, from: data)

        XCTAssertTrue(decoded.whitelistedTokens.isEmpty)
        XCTAssertTrue(decoded.whitelistedPrograms.isEmpty)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
            "maxSOLPerTransaction": 2.5,
            "maxUSDPerTransaction": 250.0,
            "dailyTransactionLimit": 10,
            "dailyUSDLimit": 1000.0,
            "whitelistedTokens": [],
            "whitelistedPrograms": ["11111111111111111111111111111111"],
            "cooldownSeconds": 3
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(GuardrailsConfig.self, from: json)

        XCTAssertEqual(config.maxSOLPerTransaction, 2.5)
        XCTAssertEqual(config.maxUSDPerTransaction, 250.0)
        XCTAssertEqual(config.dailyTransactionLimit, 10)
        XCTAssertEqual(config.dailyUSDLimit, 1000.0)
        XCTAssertEqual(config.cooldownSeconds, 3)
        XCTAssertEqual(config.whitelistedPrograms, ["11111111111111111111111111111111"])
    }

    // MARK: - Static Properties

    func testDefaultWhitelistedPrograms() {
        let programs = GuardrailsConfig.defaultWhitelistedPrograms
        XCTAssertFalse(programs.isEmpty)

        // System Program
        XCTAssertTrue(programs.contains("11111111111111111111111111111111"))
        // Token Program
        XCTAssertTrue(programs.contains("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"))
        // Jupiter v6
        XCTAssertTrue(programs.contains("JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"))
        // Compute Budget
        XCTAssertTrue(programs.contains("ComputeBudget111111111111111111111111111111"))
    }

    func testDefaultWhitelistedTokenSymbols() {
        let symbols = GuardrailsConfig.defaultWhitelistedTokenSymbols
        XCTAssertTrue(symbols.contains("SOL"))
        XCTAssertTrue(symbols.contains("USDC"))
        XCTAssertTrue(symbols.contains("USDT"))
    }

    // MARK: - AppConfig Integration

    func testAppConfigGuardrailsPersistence() async throws {
        let tempDir = NSTemporaryDirectory() + "DeadboltCoreTests_Guardrails_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = tempDir + "/config.json"

        // Save custom guardrails
        let config1 = AppConfig(filePath: filePath)
        let guardrails = GuardrailsConfig(
            maxSOLPerTransaction: 1.0,
            maxUSDPerTransaction: 100.0,
            dailyTransactionLimit: 5,
            dailyUSDLimit: 500.0,
            whitelistedTokens: ["So11111111111111111111111111111111111111112"],
            whitelistedPrograms: ["11111111111111111111111111111111"],
            cooldownSeconds: 30
        )
        await config1.update(guardrails: guardrails)
        try await config1.save()

        // Load in new instance
        let config2 = AppConfig(filePath: filePath)
        try await config2.load()

        let loaded = await config2.guardrails
        XCTAssertEqual(loaded.maxSOLPerTransaction, 1.0)
        XCTAssertEqual(loaded.maxUSDPerTransaction, 100.0)
        XCTAssertEqual(loaded.dailyTransactionLimit, 5)
        XCTAssertEqual(loaded.dailyUSDLimit, 500.0)
        XCTAssertEqual(loaded.whitelistedTokens, ["So11111111111111111111111111111111111111112"])
        XCTAssertEqual(loaded.whitelistedPrograms, ["11111111111111111111111111111111"])
        XCTAssertEqual(loaded.cooldownSeconds, 30)
    }

    func testAppConfigAPIToken() async throws {
        let tempDir = NSTemporaryDirectory() + "DeadboltCoreTests_Token_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = tempDir + "/config.json"
        let config = AppConfig(filePath: filePath)

        // Default: no token
        let noToken = await config.apiToken
        XCTAssertNil(noToken)

        // Generate a token
        let token = await config.generateAPIToken()
        XCTAssertTrue(token.hasPrefix("db_"))
        XCTAssertEqual(token.count, 3 + 32) // "db_" + 16 bytes hex

        // Validate
        let valid = await config.validateToken(token)
        XCTAssertTrue(valid)

        // Validate wrong token
        let invalid = await config.validateToken("db_wrong")
        XCTAssertFalse(invalid)

        // Persist and reload
        try await config.save()
        let config2 = AppConfig(filePath: filePath)
        try await config2.load()
        let loadedToken = await config2.apiToken
        XCTAssertEqual(loadedToken, token)
    }

    func testAppConfigTokenValidation() async {
        let tempDir = NSTemporaryDirectory() + "DeadboltCoreTests_TokenVal_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let config = AppConfig(filePath: tempDir + "/config.json")

        // No token = invalid
        let invalid = await config.validateToken("anything")
        XCTAssertFalse(invalid)

        // Set token manually
        await config.update(apiToken: "db_abc123")
        let valid = await config.validateToken("db_abc123")
        XCTAssertTrue(valid)

        // Clear token
        await config.update(apiToken: nil)
        let cleared = await config.validateToken("db_abc123")
        XCTAssertFalse(cleared)
    }
}

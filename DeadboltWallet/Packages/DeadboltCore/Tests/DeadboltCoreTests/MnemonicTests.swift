import XCTest
import CryptoKit
@testable import DeadboltCore

final class MnemonicTests: XCTestCase {

    // MARK: - Word List Validation

    func testWordListHas2048Words() {
        XCTAssertEqual(Mnemonic.wordList.count, 2048, "BIP39 English word list must have exactly 2048 words")
    }

    func testWordListFirstAndLastWords() {
        XCTAssertEqual(Mnemonic.wordList.first, "abandon")
        XCTAssertEqual(Mnemonic.wordList.last, "zoo")
    }

    // MARK: - P8-003: 12-Word Generation

    func testGenerate12Words() throws {
        let words = try Mnemonic.generate(wordCount: 12)
        XCTAssertEqual(words.count, 12, "Should generate 12 words")

        // All words must be in the word list
        for word in words {
            XCTAssertTrue(Mnemonic.wordList.contains(word),
                "\"\(word)\" is not in the BIP39 word list")
        }

        // Generated mnemonic should be valid
        XCTAssertTrue(Mnemonic.validate(words: words),
            "Generated 12-word mnemonic should pass validation")
    }

    // MARK: - P8-003: 24-Word Generation

    func testGenerate24Words() throws {
        let words = try Mnemonic.generate(wordCount: 24)
        XCTAssertEqual(words.count, 24, "Should generate 24 words")

        for word in words {
            XCTAssertTrue(Mnemonic.wordList.contains(word),
                "\"\(word)\" is not in the BIP39 word list")
        }

        XCTAssertTrue(Mnemonic.validate(words: words),
            "Generated 24-word mnemonic should pass validation")
    }

    func testGenerateInvalidWordCountThrows() {
        XCTAssertThrowsError(try Mnemonic.generate(wordCount: 15)) { error in
            guard case SolanaError.invalidMnemonic = error else {
                XCTFail("Expected invalidMnemonic, got \(error)")
                return
            }
        }
    }

    func testGeneratedMnemonicsAreUnique() throws {
        let words1 = try Mnemonic.generate(wordCount: 12)
        let words2 = try Mnemonic.generate(wordCount: 12)
        XCTAssertNotEqual(words1, words2, "Two generated mnemonics should differ")
    }

    // MARK: - P8-004: Validation

    func testValidateKnownMnemonic() {
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)
        XCTAssertTrue(Mnemonic.validate(words: words),
            "The standard BIP39 test mnemonic should be valid")
    }

    func testValidateCatchesBadWord() {
        var words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)
        words[5] = "notaword"
        XCTAssertFalse(Mnemonic.validate(words: words),
            "Mnemonic with invalid word should fail validation")
    }

    func testValidateCatchesWrongWordCount() {
        let words = ["abandon", "abandon", "abandon", "abandon", "abandon"]
        XCTAssertFalse(Mnemonic.validate(words: words),
            "5-word mnemonic should fail validation")
    }

    func testValidateCatchesBadChecksum() {
        // All valid words but wrong checksum: change last word
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"
            .split(separator: " ").map(String.init)
        // "abandon" x12 has wrong checksum (the correct 12th word for all-abandon is "about")
        XCTAssertFalse(Mnemonic.validate(words: words),
            "Mnemonic with bad checksum should fail validation")
    }

    // MARK: - BIP39 Seed Derivation

    func testToSeedKnownVector() throws {
        // Known BIP39 test vector:
        // Mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        // Passphrase: ""
        // Expected seed (hex): 5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)

        let seed = try Mnemonic.toSeed(words: words, passphrase: "")
        XCTAssertEqual(seed.count, 64, "BIP39 seed should be 64 bytes")

        let expectedHex = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        let actualHex = seed.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHex, expectedHex,
            "BIP39 seed should match known test vector")
    }

    // MARK: - SLIP-0010 / Solana Derivation (m/44'/501'/0'/0')

    func testDeriveKeypairKnownVector() throws {
        // Known test vector:
        // Mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        // Passphrase: ""
        // Derivation path: m/44'/501'/0'/0' (SLIP-0010 Ed25519)
        // Expected Solana address: HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)

        let keypair = try Mnemonic.deriveKeypair(words: words, passphrase: "")

        XCTAssertEqual(keypair.seed.count, 32, "Derived seed should be 32 bytes")
        XCTAssertEqual(keypair.publicKey.data.count, 32, "Public key should be 32 bytes")

        // Verify the derived address matches the known expected value
        let expectedAddress = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"
        XCTAssertEqual(keypair.publicKey.base58, expectedAddress,
            "Derived address should match Phantom/Solflare derivation for this mnemonic")

        // Verify the seed matches expected derived key
        let expectedSeedHex = "37df573b3ac4ad5b522e064e25b63ea16bcbe79d449e81a0268d1047948bb445"
        let actualSeedHex = keypair.seed.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualSeedHex, expectedSeedHex,
            "Derived private key seed should match known value")
    }

    func testDeriveKeypairIsDeterministic() throws {
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)

        let keypair1 = try Mnemonic.deriveKeypair(words: words)
        let keypair2 = try Mnemonic.deriveKeypair(words: words)

        XCTAssertEqual(keypair1.seed, keypair2.seed)
        XCTAssertEqual(keypair1.publicKey, keypair2.publicKey)
    }

    func testDeriveKeypairDifferentPassphrasesProduceDifferentKeys() throws {
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)

        let keypair1 = try Mnemonic.deriveKeypair(words: words, passphrase: "")
        let keypair2 = try Mnemonic.deriveKeypair(words: words, passphrase: "mypassphrase")

        XCTAssertNotEqual(keypair1.seed, keypair2.seed,
            "Different passphrases should produce different seeds")
        XCTAssertNotEqual(keypair1.publicKey, keypair2.publicKey,
            "Different passphrases should produce different public keys")
    }

    func testDeriveKeypairCanSign() async throws {
        let words = try Mnemonic.generate(wordCount: 12)
        let keypair = try Mnemonic.deriveKeypair(words: words)

        // Create a signer and verify round-trip
        let signer = try SoftwareSigner(keypair: keypair)
        let message = Data("test message".utf8)
        let signature = try await signer.sign(message: message)

        XCTAssertEqual(signature.count, 64, "Ed25519 signature should be 64 bytes")

        let valid = SoftwareSigner.verify(signature: signature, message: message, publicKey: keypair.publicKey)
        XCTAssertTrue(valid, "Signature should verify correctly")
    }

    // MARK: - P8-004: Import from Phrase

    func testImportFromPhraseWithInvalidWordsThrows() {
        let badWords = ["abandon", "abandon", "abandon", "abandon", "abandon",
                        "abandon", "abandon", "abandon", "abandon", "abandon",
                        "abandon", "abandon"]  // bad checksum
        XCTAssertThrowsError(try Mnemonic.importFromPhrase(words: badWords)) { error in
            guard case SolanaError.invalidMnemonic = error else {
                XCTFail("Expected invalidMnemonic, got \(error)")
                return
            }
        }
    }

    // MARK: - Entropy-to-Words Round Trip

    func testEntropyToWordsKnownVector() throws {
        // Known BIP39 test: 16 bytes of all zeros → "abandon" x11 + "about"
        let entropy = Data(repeating: 0x00, count: 16)
        let words = try Mnemonic.wordsFromEntropy(entropy)
        let expected = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)
        XCTAssertEqual(words, expected,
            "All-zero entropy should produce 'abandon...about'")
    }
}

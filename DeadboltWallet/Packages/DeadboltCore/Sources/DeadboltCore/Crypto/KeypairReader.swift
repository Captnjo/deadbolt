import Foundation

public struct Keypair: Sendable {
    public let seed: Data       // 32 bytes (Ed25519 private key seed)
    public let publicKey: SolanaPublicKey
    public let sourcePath: String?

    public init(seed: Data, publicKey: SolanaPublicKey, sourcePath: String? = nil) {
        self.seed = seed
        self.publicKey = publicKey
        self.sourcePath = sourcePath
    }
}

public enum KeypairReader {
    /// Standard directories to scan for keypair files
    public static var keypairDirectories: [String] {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.config/solana/deadbolt",
            "\(home)/.config/solana",
        ]
        #else
        // On iOS, keypair files are stored in the app's data directory
        return [
            DeadboltDirectories.dataDirectory + "/keypairs",
        ]
        #endif
    }

    /// Read a keypair from a JSON file containing an array of 64 integers
    public static func read(from path: String) throws -> Keypair {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SolanaError.keypairFileNotFound(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let bytes: [UInt8]
        do {
            let ints = try JSONDecoder().decode([Int].self, from: data)
            // Validate all values are in valid byte range
            for (i, value) in ints.enumerated() {
                guard value >= 0 && value <= 255 else {
                    throw SolanaError.keypairParseError("Byte at index \(i) out of range: \(value) (expected 0-255)")
                }
            }
            bytes = ints.map { UInt8($0) }
        } catch let error as SolanaError {
            throw error
        } catch {
            throw SolanaError.keypairParseError("Not a valid JSON array of integers")
        }

        guard bytes.count == 64 else {
            throw SolanaError.invalidKeypairLength(bytes.count)
        }

        let seed = Data(bytes[0..<32])
        let pubKeyBytes = Data(bytes[32..<64])
        let publicKey = try SolanaPublicKey(data: pubKeyBytes)

        return Keypair(seed: seed, publicKey: publicKey, sourcePath: path)
    }

    /// Discover all keypair JSON files in standard directories
    public static func discoverKeypairs() -> [Keypair] {
        var keypairs: [Keypair] = []
        let fm = FileManager.default

        for dir in keypairDirectories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".json") {
                let path = (dir as NSString).appendingPathComponent(file)
                if let keypair = try? read(from: path) {
                    keypairs.append(keypair)
                }
            }
        }

        return keypairs
    }
}

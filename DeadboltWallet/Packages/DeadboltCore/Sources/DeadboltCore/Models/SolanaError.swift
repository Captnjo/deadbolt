import Foundation

public enum SolanaError: LocalizedError {
    case invalidBase58Character(Character)
    case invalidPublicKeyLength(Int)
    case invalidKeypairLength(Int)
    case publicKeyMismatch
    case keypairFileNotFound(String)
    case keypairParseError(String)
    case keychainError(OSStatus)
    case keychainItemNotFound
    case rpcError(code: Int, message: String)
    case httpError(statusCode: Int)
    case decodingError(String)
    case noWalletLoaded
    case priceUnavailable(String)
    case pdaNotFound
    case pdaOnCurve
    case pdaSeedTooLong(Int)
    case tokenAccountNotFound(String)
    case vanityMaxAttemptsReached
    case invalidMnemonic(String)
    case invalidAddressBookEntry(String)
    case authenticationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBase58Character(let c):
            return "Invalid Base58 character: '\(c)'"
        case .invalidPublicKeyLength(let n):
            return "Invalid public key length: expected 32 bytes, got \(n)"
        case .invalidKeypairLength(let n):
            return "Invalid keypair length: expected 64 bytes, got \(n)"
        case .publicKeyMismatch:
            return "Derived public key does not match keypair file"
        case .keypairFileNotFound(let path):
            return "Keypair file not found: \(path)"
        case .keypairParseError(let msg):
            return "Failed to parse keypair: \(msg)"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .keychainItemNotFound:
            return "Keychain item not found"
        case .rpcError(let code, let message):
            return "RPC error \(code): \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let msg):
            return "Decoding error: \(msg)"
        case .noWalletLoaded:
            return "No wallet loaded"
        case .priceUnavailable(let token):
            return "Price unavailable for \(token)"
        case .pdaNotFound:
            return "Could not find a valid program-derived address"
        case .pdaOnCurve:
            return "Derived address is on the Ed25519 curve (not a valid PDA)"
        case .pdaSeedTooLong(let n):
            return "PDA seed too long: \(n) bytes (max 32)"
        case .tokenAccountNotFound(let address):
            return "Token account not found: \(address)"
        case .vanityMaxAttemptsReached:
            return "Vanity address: max attempts reached without finding a match"
        case .invalidMnemonic(let reason):
            return "Invalid mnemonic: \(reason)"
        case .invalidAddressBookEntry(let reason):
            return "Invalid address book entry: \(reason)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        }
    }
}

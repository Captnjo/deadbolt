/// Validate a Solana Base58 address (32 bytes when decoded).
bool isValidSolanaAddress(String address) {
  if (address.isEmpty) return false;
  // Base58 alphabet check
  final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
  if (!base58Regex.hasMatch(address)) return false;
  // A 32-byte key in Base58 is 32–44 characters
  if (address.length < 32 || address.length > 44) return false;
  return true;
}

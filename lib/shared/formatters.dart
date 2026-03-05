class Formatters {
  Formatters._();

  /// Format lamports as SOL with up to 4 decimals, trailing zeros trimmed.
  static String formatSol(int lamports) {
    final sol = lamports / 1e9;
    var s = sol.toStringAsFixed(4);
    // Trim trailing zeros after decimal point
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// Format a USD value as $X.XX.
  static String formatUsd(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  /// Format a token amount with adaptive decimals.
  static String formatTokenAmount(double amount) {
    if (amount >= 1000000) return amount.toStringAsFixed(0);
    if (amount >= 1) return amount.toStringAsFixed(2);
    return amount.toStringAsFixed(6);
  }

  /// Shorten an address: ABCD...WXYZ.
  static String shortAddress(String address) {
    if (address.length <= 8) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }
}

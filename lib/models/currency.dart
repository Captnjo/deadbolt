enum DisplayCurrency {
  usd(code: 'usd', symbol: '\$', name: 'US Dollar', prefixed: true, decimals: 2),
  eur(code: 'eur', symbol: '\u20AC', name: 'Euro', prefixed: true, decimals: 2),
  gbp(code: 'gbp', symbol: '\u00A3', name: 'British Pound', prefixed: true, decimals: 2),
  jpy(code: 'jpy', symbol: '\u00A5', name: 'Japanese Yen', prefixed: true, decimals: 0),
  cny(code: 'cny', symbol: '\u00A5', name: 'Chinese Yuan', prefixed: true, decimals: 2),
  krw(code: 'krw', symbol: '\u20A9', name: 'Korean Won', prefixed: true, decimals: 0),
  aud(code: 'aud', symbol: 'A\$', name: 'Australian Dollar', prefixed: true, decimals: 2),
  cad(code: 'cad', symbol: 'C\$', name: 'Canadian Dollar', prefixed: true, decimals: 2),
  chf(code: 'chf', symbol: 'CHF', name: 'Swiss Franc', prefixed: true, decimals: 2),
  btc(code: 'btc', symbol: '\u20BF', name: 'Bitcoin', prefixed: true, decimals: 8),
  sol(code: 'sol', symbol: 'SOL', name: 'Solana', prefixed: false, decimals: 4);

  const DisplayCurrency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.prefixed,
    required this.decimals,
  });

  final String code;
  final String symbol;
  final String name;
  final bool prefixed;
  final int decimals;

  static DisplayCurrency fromCode(String code) {
    return DisplayCurrency.values.firstWhere(
      (c) => c.code == code,
      orElse: () => DisplayCurrency.usd,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token.dart';
import '../services/helius_das_service.dart';
import 'balance_provider.dart';
import 'jupiter_token_list_provider.dart';
import 'network_provider.dart';

/// In-memory cache for Helius DAS lookups. Survives provider re-evaluations.
final Map<String, TokenDefinition?> _dasCache = {};

/// Resolves token metadata for a single mint address.
/// Checks: wallet balances → Jupiter list → DAS cache → Helius DAS.
/// Prefers sources that have a logoUri; falls through if logo is missing.
final tokenMetadataProvider =
    FutureProvider.family<TokenDefinition?, String>((ref, mint) async {
  TokenDefinition? best;

  // 1. Check wallet balances
  final portfolio = ref.watch(balanceProvider).valueOrNull;
  final walletMatch = portfolio?.tokenBalances
      .where((tb) => tb.definition.mint == mint)
      .firstOrNull;
  if (walletMatch != null) {
    if (walletMatch.definition.logoUri != null) return walletMatch.definition;
    best = walletMatch.definition;
  }

  // 2. Check Jupiter list (has logoUri for verified tokens)
  final jupiterTokens = ref.watch(jupiterTokenListProvider).valueOrNull;
  final jupiterMatch =
      jupiterTokens?.where((d) => d.mint == mint).firstOrNull;
  if (jupiterMatch != null) {
    if (jupiterMatch.logoUri != null) return jupiterMatch;
    best ??= jupiterMatch;
  }

  // 3. Check DAS cache (avoids repeat network calls)
  if (_dasCache.containsKey(mint)) {
    return _dasCache[mint] ?? best;
  }

  // 4. Fetch from Helius DAS (one-time per mint)
  final net = ref.read(networkProvider);
  if (net.heliusApiKey.isEmpty) return best;

  final das = HeliusDasService(apiKey: net.heliusApiKey);
  try {
    final asset = await das.getAsset(mint);
    if (asset == null) {
      _dasCache[mint] = best;
      return best;
    }

    final content = asset['content'] as Map<String, dynamic>?;
    final metadata = content?['metadata'] as Map<String, dynamic>?;
    final links = content?['links'] as Map<String, dynamic>?;

    final resolved = TokenDefinition(
      mint: mint,
      name: metadata?['name'] as String? ?? best?.name ?? '',
      symbol: metadata?['symbol'] as String? ?? best?.symbol ?? '',
      decimals: best?.decimals ?? 0,
      logoUri: links?['image'] as String?,
    );
    _dasCache[mint] = resolved;
    return resolved;
  } catch (_) {
    _dasCache[mint] = best;
    return best;
  } finally {
    das.dispose();
  }
});

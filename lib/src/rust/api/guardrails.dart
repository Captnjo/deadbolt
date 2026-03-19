// Typed stub for guardrails bridge functions.
// Will be replaced by FRB codegen when Flutter toolchain available.

class GuardrailsConfigDto {
  final bool enabled;
  final List<String> tokenWhitelist;

  const GuardrailsConfigDto({
    required this.enabled,
    required this.tokenWhitelist,
  });

  GuardrailsConfigDto copyWith({
    bool? enabled,
    List<String>? tokenWhitelist,
  }) {
    return GuardrailsConfigDto(
      enabled: enabled ?? this.enabled,
      tokenWhitelist: tokenWhitelist ?? this.tokenWhitelist,
    );
  }
}

GuardrailsConfigDto getGuardrailsConfig() =>
    throw UnimplementedError('Requires FRB codegen');

Future<void> updateGuardrailsConfig({
  required GuardrailsConfigDto dto,
}) =>
    throw UnimplementedError('Requires FRB codegen');

String? checkManualTransaction({
  String? mint,
  String? outputMint,
}) =>
    throw UnimplementedError('Requires FRB codegen');

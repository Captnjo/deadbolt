---
phase: 04-guardrails-engine
plan: "02"
subsystem: flutter-ui
tags: [guardrails, settings, riverpod, frb-stub, flutter]
dependency_graph:
  requires: [04-01]
  provides: [guardrails-settings-ui, guardrails-provider, guardrails-frb-stub]
  affects: [lib/features/settings/settings_screen.dart]
tech_stack:
  added: []
  patterns: [ConsumerStatefulWidget, NotifierProvider, DraggableScrollableSheet, AnimatedCrossFade]
key_files:
  created:
    - lib/src/rust/api/guardrails.dart
    - lib/providers/guardrails_provider.dart
    - lib/features/settings/guardrails_settings_section.dart
  modified:
    - lib/features/settings/settings_screen.dart
decisions:
  - "GuardrailsSettingsSection uses activeThumbColor (not activeColor) on Switch — activeColor deprecated after Flutter 3.31"
  - "Token row in whitelist uses symbol initial in CircleAvatar — TokenDefinition has no logoUri field, plan reference was aspirational"
  - "Empty token list in sheet shows 'No tokens in your wallet yet' without wallet watch — reuses balanceProvider.valueOrNull fallback pattern"
metrics:
  duration_minutes: 2
  completed_date: "2026-03-19"
  tasks_completed: 2
  files_changed: 4
requirements_satisfied: [GRDL-01, GRDL-03, GRDL-07]
---

# Phase 04 Plan 02: Guardrails Settings UI Summary

**One-liner:** Flutter guardrails settings UI with FRB stub, Riverpod provider, master toggle (auth-gated OFF), and expandable token whitelist management using balanceProvider for held token resolution.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | FRB typed stub + GuardrailsNotifier provider | 862aed7 | lib/src/rust/api/guardrails.dart, lib/providers/guardrails_provider.dart |
| 2 | GuardrailsSettingsSection widget + integrate into settings screen | 7b8091d | lib/features/settings/guardrails_settings_section.dart, lib/features/settings/settings_screen.dart |

## What Was Built

**Task 1 — FRB typed stub + provider:**
- `lib/src/rust/api/guardrails.dart`: `GuardrailsConfigDto` with `enabled`, `tokenWhitelist`, and `copyWith`; stub functions `getGuardrailsConfig`, `updateGuardrailsConfig`, `checkManualTransaction` all throw `UnimplementedError` until FRB codegen runs
- `lib/providers/guardrails_provider.dart`: `GuardrailsNotifier` (extends `Notifier`) with `setEnabled`, `addToken`, `removeToken`, `refresh`; falls back to `enabled=true, tokenWhitelist=[]` on bridge error; exported as `guardrailsProvider`

**Task 2 — Settings section widget:**
- `GuardrailsSettingsSection`: `ConsumerStatefulWidget` with section divider/header, master toggle (`Switch` with `activeThumbColor: BrandColors.primary`), disabled subtitle ("All guardrails disabled" in `BrandColors.error`) when OFF
- Token Whitelist expandable `Card` using `AnimatedCrossFade` (200ms), collapsed shows count or "No restrictions — all SPL tokens allowed"
- Expanded content: per-token rows with `CircleAvatar` (symbol initial), symbol name, truncated mint, `IconButton(tooltip: 'Remove token')`
- Add Token bottom sheet via `DraggableScrollableSheet`: search held tokens from `balanceProvider`, exclude already-whitelisted mints; paste mint address field with 44-char validation ("Invalid mint address (must be 44 characters)")
- Integrated into `settings_screen.dart` immediately after `SecuritySettingsSection`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Switch.activeColor deprecated**
- **Found during:** Task 2 dart analyze
- **Issue:** `activeColor` deprecated after Flutter 3.31 — `dart analyze` reported deprecation info
- **Fix:** Changed to `activeThumbColor: BrandColors.primary` (direct replacement)
- **Files modified:** lib/features/settings/guardrails_settings_section.dart
- **Commit:** 7b8091d

**2. [Rule 1 - Bug] TokenDefinition.logoUri does not exist**
- **Found during:** Task 2 implementation (pre-compile review)
- **Issue:** Plan's token row code referenced `tb.definition.logoUri` and `NetworkImage(logoUri)` but `TokenDefinition` in `lib/models/token.dart` has no `logoUri` field — would cause compile error
- **Fix:** Token rows use `CircleAvatar` with symbol initial only; `NetworkImage` removed
- **Files modified:** lib/features/settings/guardrails_settings_section.dart
- **Commit:** 7b8091d

## Verification Results

```
dart analyze lib/src/rust/api/guardrails.dart lib/providers/guardrails_provider.dart
  lib/features/settings/guardrails_settings_section.dart lib/features/settings/settings_screen.dart
=> No issues found!
```

## Self-Check: PASSED

- lib/src/rust/api/guardrails.dart: FOUND
- lib/providers/guardrails_provider.dart: FOUND
- lib/features/settings/guardrails_settings_section.dart: FOUND
- lib/features/settings/settings_screen.dart: FOUND (modified)
- Commit 862aed7: FOUND
- Commit 7b8091d: FOUND

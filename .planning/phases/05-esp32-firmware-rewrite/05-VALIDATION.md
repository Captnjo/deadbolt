---
phase: 5
slug: esp32-firmware-rewrite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + integration_test (Flutter), PlatformIO test (ESP32 C++) |
| **Config file** | `pubspec.yaml` (Flutter), `platformio.ini` (firmware) |
| **Quick run command** | `flutter test test/` |
| **Full suite command** | `flutter test && cd esp32 && pio test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/`
- **After every plan wave:** Run `flutter test && cd esp32 && pio test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | HWLT-04 | unit | `pio test -e native -f test_entropy` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | HWLT-01 | unit | `pio test -e native -f test_bip39` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 1 | HWLT-02 | unit | `pio test -e native -f test_slip0010` | ❌ W0 | ⬜ pending |
| 05-01-04 | 01 | 1 | HWLT-05 | unit | `pio test -e native -f test_nvs_crypto` | ❌ W0 | ⬜ pending |
| 05-01-05 | 01 | 1 | HWLT-06 | unit | `pio test -e native -f test_factory_reset` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 1 | HWLT-03 | unit | `flutter test test/hardware/ble_protocol_test.dart` | ❌ W0 | ⬜ pending |
| 05-02-02 | 02 | 1 | INFR-01 | unit | `flutter test test/hardware/auto_connect_test.dart` | ❌ W0 | ⬜ pending |
| 05-02-03 | 02 | 1 | INFR-02 | integration | `flutter test test/hardware/pubkey_verify_test.dart` | ❌ W0 | ⬜ pending |
| 05-03-01 | 03 | 2 | INFR-03 | unit | `flutter test test/hardware/mnemonic_display_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `esp32/test/test_entropy/` — entropy verification stubs
- [ ] `esp32/test/test_bip39/` — BIP39 mnemonic generation stubs
- [ ] `esp32/test/test_slip0010/` — SLIP-0010 derivation stubs
- [ ] `esp32/test/test_nvs_crypto/` — NVS encryption stubs
- [ ] `esp32/test/test_factory_reset/` — factory reset stubs
- [ ] `test/hardware/ble_protocol_test.dart` — BLE protocol stubs
- [ ] `test/hardware/auto_connect_test.dart` — auto-connect stubs
- [ ] `test/hardware/pubkey_verify_test.dart` — pubkey verification stubs
- [ ] `test/hardware/mnemonic_display_test.dart` — mnemonic display stubs

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Physical BLE pairing flow | HWLT-03 | Requires real ESP32 hardware | Pair ESP32 via BLE, verify connection established |
| Mnemonic shown exactly once | HWLT-01 | Requires visual confirmation on device | Generate keypair, verify mnemonic displays then clears |
| Screenshot prevention | INFR-03 | macOS-specific window capture behavior | Attempt screenshot during mnemonic display, verify blocked |
| Factory reset erases NVS | HWLT-06 | Requires hardware flash inspection | Trigger factory reset, verify NVS partition erased via serial |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

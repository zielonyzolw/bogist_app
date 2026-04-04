# bogist_app

Flutter Android app for reverse-engineering the BLE protocol of a **Bogist** electric scooter.
Connects to the scooter over BLE, reads telemetry notifications, and lets you probe write
characteristics with structured, session-based test tooling.

> **All commands and parsed field interpretations are unverified probes.**
> Do not test while riding or with wheels able to spin freely.

---

## Changelog

### Phase 5 — Auto Test Lab (automated sequence runner)
*Implemented: 2026-04-04*

**New screen: Auto Test Lab** (accessible from the Dashboard)

**Candidate generation** (`auto_test_candidate.dart`)
- Four generation strategies, all capped at a configurable max (default 20, hard max 20):
  - *Manual grid* — reuses the existing A1–C4 entries from `kCommandMap` (12 candidates)
  - *Byte[2] sweep* — fixes all bytes; sweeps byte[2] through 11 human-selected values (not a brute-force 256-value scan)
  - *Byte[3] sweep* — same idea for byte[3] (4 values)
  - *Dual sweep* — sweeps both byte[2] and byte[3]; result is capped to prevent oversized sessions
- Default base template is `AA 55 00 00 … 00` (20 bytes, AA 55 header, rest 0x00)
- All candidates labelled `[EXP]` / `[EXPERIMENTAL]` throughout the code and UI
- No motor control, throttle, braking, or speed-limit payloads

**Auto-test controller** (`auto_test_controller.dart`)
- Dedicated `AutoTestController` (`ChangeNotifier`) — does not touch BLE transport or `SessionService`; owns its own typed log (`List<AutoTestEntry>`)
- State machine: `idle → running ↔ paused → stopped / completed / error`
- 3-second inter-send interval (constant `AutoTestController.intervalMs`); countdown is preserved across pause/resume
- Per-entry data: index, label, payload hex, raw hex, write mode, checksum mode, sent-at timestamp, frame types before TX (2 s window), frame types after TX, `newFrameDetected` flag, user reaction
- BLE disconnect listener — auto-stops with error message if connection drops during a run

**Safety gates**
- Start button disabled when not connected
- Pre-start safety confirmation dialog (required): red warning box + "I understand — Start" button
- Speed-warning dialog: if parsed speed > 0, shows an override-required warning before the confirmation dialog (with a note that the speed field is unverified)
- Session hard-capped at 20 tests per run; configurable down to 3 via slider

**Stop conditions** (all independently toggleable)
- Manual STOP button — always visible and red; interrupts immediately, finalises the current entry
- BLE disconnect — automatic stop
- Send error — stops with error status
- *Stop on new frame type detected* — stops after the RX window if a new Frame-X appears post-TX
- *Stop when reaction marked* — stops as soon as the user marks any reaction on an entry

**UI highlights**
- Permanent red safety banner pinned to the top of the screen
- `_StatusControlPanel` always visible above the scroll area: status chip (IDLE/RUNNING/PAUSED/STOPPED/DONE/ERROR), test N of M counter, big red STOP button, Pause/Resume buttons
- `_ProgressCard` (shown while running/paused): dual progress bars (overall + per-send countdown), current payload hex, write mode and checksum labels
- `_SettingsPanel` (shown when idle): source dropdown, max-tests slider, write mode, checksum, pad-to-20, stop conditions
- `_CandidatePreview` (shown when idle): lists first 5 candidates with overflow count
- `_LogSection`: one card per completed entry; cards turn orange when a new frame type was detected, teal when reaction is marked; quick-tap reaction chips (No reaction / Beep / Light changed / Mode changed / Unknown reaction / Reaction noticed)
- Frame-diff line per entry: `before: Frame-A / after: Frame-A, Frame-B  ★ NEW: Frame-B`

**Architecture**
- `AutoTestController` injected via `ChangeNotifierProxyProvider<BleService, AutoTestController>` in `app.dart`
- BLE writes reuse `BleService.writeCommand()` — all TX appears in the unified BLE log with `[Auto-N]` prefix
- Frame classification reuses `BleService.frameClassifier` and `rxFramesSince()`

---

### Phase 4 — TX tooling, frame classification, experiment diff
*Implemented: 2026-04-04*

**TX write tools**
- Write-mode selector: `writeWithResponse` (ACK) vs `writeWithoutResponse` (no ACK), shown as a segmented button in the TX Settings panel.
- Checksum append: None / XOR / SUM8 / SUM16 LE / CRC16-Modbus — appended to the raw payload before sending.
- Pad-to-20 toggle: fills the payload with `0x00` to 20 bytes (applied after checksum).
- Custom hex field now shows a live payload preview with final byte count after checksum and padding are applied.

**Frame classification**
- `FrameClassifier` auto-assigns stable labels (`Frame-A`, `Frame-B`, `Frame-C`, …) to incoming AB02 frames based on bytes[2..5] (the 4-byte structural key after the `AA 55` header).
- Frame-type counts displayed live in the Test Lab (`Frame-A(12) Frame-B(3) …`).
- Each RX entry in the BLE Log now carries a coloured category badge (e.g. `Frame-A`).
- All parser field interpretations (`speed`, `batteryRaw`) marked explicitly as **TENTATIVE / UNVERIFIED** in code comments and the debug log.

**Experiment diff (before / after TX)**
- On every send, the app snapshots frame types seen in the 2 seconds before TX.
- The observation sheet computes and displays a live diff once the 3-second RX collection window closes: `NEW after TX`, `GONE after TX`, `unchanged`.
- `TestRecord` stores `framesBefore`, `newFrameTypes`, and `frameDiff` — all exported in session JSON.

**Session record improvements**
- Records now include `originalPayloadHex` (before checksum/padding), `writeMode`, and `checksumMode`.
- Record tiles show ACK / noACK and checksum badges, plus the frame-diff string.

---

### Phase 3 — Structured reverse-engineering test lab
*Implemented: 2026-04-04*

- Replaced ad-hoc command buttons with a neutral **3×4 grid** (`A1`–`C4`). Each button sends exactly one candidate payload; labels are intentionally non-descriptive until confirmed by capture evidence.
- Command payloads live in `command_map.dart` — edit that file to change what each button sends; the UI updates automatically.
- **Session-based structured logging**: `SessionService` manages a `TestSession` containing ordered `TestRecord`s.
  - Each record captures: button label, payload hex, scooter state before/after, RX frames received in a 3-second collection window, and a user observation.
  - `TestRecord.isFinalized` tracks whether an observation has been submitted.
- **Observation sheet**: bottom-sheet shown after every send with a 3-second countdown, live RX frame list, quick-pick tags (`No reaction`, `Beep`, `Lights changed`, …), and a free-text notes field.
- **JSON export**: `SessionService.exportJson()` produces pretty-printed JSON with full record data; copy-to-clipboard and in-app viewer available from the Test Lab.
- Frame comparison infrastructure introduced (`rxFramesSince`, `ScooterStateSnapshot`).

---

### Phase 2 — Disconnect fix, write layer, debug log
*Implemented: 2026-04-04*

- **BLE disconnect bug fixed**: subscription references are nulled *before* `cancel()` is called (`_cancelConnectionStreams()`). Post-cancel stream callbacks see a null ref and exit early, preventing race conditions and phantom reconnects.
- **Write layer added**: `BleService.writeCommand()` writes to characteristic AB01 using `writeCharacteristicWithResponse`.
- **Command/test page**: replaced placeholder with a configurable test screen (later evolved into the Test Lab in Phase 3).
- **Unified TX/RX log**: `BleLogEntry` covers both notification frames (RX) and write commands (TX). Direction badges (`RX` / `TX`) shown with contrasting colours in the Debug Log page.
- Debug Log page added — accessible from the Dashboard and later from the Test Lab app bar.

---

### Phase 1 — MVP
*Implemented: 2026-04-04*

- Flutter Android app scaffold: `flutter_reactive_ble 5.4.2`, `permission_handler 11.4.0`, `provider 6.1.5`, Material 3 green theme.
- **Android permissions**: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, `uses-feature bluetooth_le`.
- **Scan page**: lists all discovered BLE devices; BOGIST device highlighted in green; tap to connect.
- **BleService** (`ChangeNotifier`): scan, connect, disconnect, subscribe to AB02 notifications. Exposes `connectionStatus`, `scooterState`, `log`, `error`.
- **Telemetry parser** (`BogistParser`): accepts `AA 55` frames ≥ 10 bytes. Parses bytes[6–7] as candidate speed (LE uint16) and byte[8] as candidate battery raw value — both tentative.
- **Dashboard page**: live speed / battery-raw chips, last raw frame hex, connection status, Disconnect button.
- **ScooterState** + `copyWith()`, **BleFrame** value objects.

---

## Architecture

```
lib/
├── main.dart
├── app.dart                        # MultiProvider (BleService, SessionService, AutoTestController)
├── core/
│   └── constants.dart              # BLE UUIDs, log limits, RX window duration
├── features/
│   ├── analysis/
│   │   └── frame_classifier.dart   # FrameClassifier: bytes[2..5] key → Frame-A/B/C
│   ├── auto_test/
│   │   ├── auto_test_candidate.dart  # Candidate generation (4 strategies, capped at 20)
│   │   └── auto_test_controller.dart # State machine: idle→running↔paused→stopped/done
│   ├── ble/
│   │   ├── ble_log_entry.dart      # LogDirection, BleLogEntry (direction, hex, category)
│   │   └── ble_service.dart        # Central BLE ChangeNotifier
│   ├── commands/
│   │   ├── checksum.dart           # WriteMode, ChecksumMode, applyChecksum, padTo20Bytes
│   │   └── command_map.dart        # kCommandMap (A1-C4 → bytes), kButtonLayout
│   ├── scooter/
│   │   ├── ble_frame.dart          # BleFrame value object
│   │   ├── bogist_parser.dart      # AA55 frame parser (fields tentative)
│   │   └── scooter_state.dart      # ScooterState + copyWith
│   ├── session/
│   │   ├── session_service.dart    # SessionService ChangeNotifier
│   │   └── test_record.dart        # TestRecord, ScooterStateSnapshot
│   └── ui/
│       ├── scan_page.dart          # BLE scan + connect
│       ├── dashboard_page.dart     # Live telemetry + nav to Test Lab / Auto Test / Debug Log
│       ├── test_lab_page.dart      # Manual test screen (grid, settings, session, export)
│       ├── auto_test_page.dart     # Automated sequence runner UI
│       └── debug_page.dart         # Unified TX/RX log with badges
```

## BLE details

| Item | Value |
|---|---|
| Service UUID | `0000AB00-0000-1000-8000-00805F9B34FB` |
| Write characteristic (TX) | `0000AB01-0000-1000-8000-00805F9B34FB` |
| Notify characteristic (RX) | `0000AB02-0000-1000-8000-00805F9B34FB` |
| Frame header | `AA 55` |
| Candidate speed field | bytes[6–7] LE uint16 — **unverified** |
| Candidate battery field | byte[8] — **unverified** |
| Frame classification key | bytes[2–5] (4 bytes after header) |

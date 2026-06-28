# ChronoPulse Active — Developer Documentation

This document contains technical implementation details, codebase architecture, build instructions, and database schema mappings for the ChronoPulse Active Flutter application.

## 🛠️ Developer Guidelines

> [!IMPORTANT]
> **Do not build the distribution (`dist`) folder or release binaries automatically.** 
> Build compilation should only be run to verify code correctness, or if explicitly requested by the user.

---

## 🛠️ Codebase Architecture

The application is structured logically to separate presentation, data management, and state logic:

```text
lib/
├── main.dart                 # App setup, Firebase/SQLite initialization, and tab view routing
├── firebase_options.dart     # Auto-generated Firebase configuration values
├── models/
│   └── workout_engine.dart   # Core workout state machine (PREP, WORK, REST, HOLD, FINISHED)
├── screens/
│   ├── timer_screen.dart     # Workout configuration, live HUD, and active template summary
│   ├── library_screen.dart   # Workout Library list, filter pills, search, and editor sheets
│   ├── history_screen.dart   # List of workout records and weekly progress bar chart
│   ├── details_screen.dart   # Workout results table, notes editor, and heart rate line graph
│   └── profile_screen.dart   # Multi-user profile management, target limits, and sync control
└── services/
    ├── database_helper.dart  # Local SQLite database configurations and CRUD queries
    ├── sync_service.dart     # Silent anonymous auth and Firestore sync worker
    ├── bluetooth_service.dart# Bluetooth LE heart rate monitor connect & scan manager
    ├── health_service.dart   # Apple HealthKit workout and characteristics worker
    └── audio_service.dart    # Sound effect chime audio player service
```

---

## 🚀 Getting Started & Setup

### Prerequisites
- **Flutter SDK**: `>=3.0.0`
- **CocoaPods** (for iOS/macOS builds)
- A **Firebase Project** with Firestore and Anonymous Authentication enabled.

### Setup and Running

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run Code Generation** (if launcher icons or dependencies change):
   ```bash
   flutter pub run flutter_launcher_icons
   ```

3. **Configure Firebase**:
   - Place your `GoogleService-Info.plist` in the `ios/Runner` folder and link it via Xcode.
   - Place your `google-services.json` in `android/app`.

4. **Launch the Application**:
   - To launch on an emulator or connected device:
     ```bash
     flutter run
     ```
   - To build for an iOS Simulator:
     ```bash
     flutter build ios --no-codesign --simulator
     ```

### 🧪 Running Tests
The project features automated engine logic and auto-regulation unit tests:
```bash
flutter test
```

---

## 💾 Local & Remote Schema

### SQLite Cache (Version 9)
- **`profiles`**: User metadata, weight presets, default sync settings, `save_history` toggle, and WalkingPad/Treadmill settings:
  - `treadmill_enabled` (INTEGER, default `0`)
  - `treadmill_preset_1` (REAL, default `2.0`)
  - `treadmill_preset_2` (REAL, default `4.0`)
  - `treadmill_preset_3` (REAL, default `6.0`)
- **`workout_templates`**: Name, rounds, work/rest times, activity type, continuous/open-ended mode, template notes, and template-level treadmill configs:
  - `auto_regulate` (INTEGER, default `1`) — added in **Version 7**
  - `treadmill_workout` (INTEGER, default `0`) — added in **Version 9**
  - `work_speed` (REAL, default `4.0`) — added in **Version 9**
  - `rest_speed` (REAL, default `0.0`) — added in **Version 9**
- **`workouts`**: End time, rounds completed, work/rest settings, activity type, calories, notes.
- **`heart_rate_logs`**: Chronological heartbeat records linked to workouts for graphic plotting.

### SQLite Schema Migration History
- **Version 2**: Added `continuous_mode` (INTEGER) to `workout_templates`.
- **Version 3**: Added `workout_name` (TEXT) to `workouts`.
- **Version 4**: Added `health_enabled` (INTEGER) to `profiles`.
- **Version 5**: Added `activity_type` (TEXT) to `workout_templates` and `workouts`.
- **Version 6**: Added `save_history` (INTEGER) to `profiles`.
- **Version 7**: Added `auto_regulate` (INTEGER) to `workout_templates`.
- **Version 8**: Added `treadmill_enabled`, `treadmill_preset_1`, `treadmill_preset_2`, and `treadmill_preset_3` to `profiles`.
- **Version 9**: Added `treadmill_workout`, `work_speed`, and `rest_speed` to `workout_templates`.

### Firestore Collections
- **`/profiles/{name}`**: Holds profile presets and treadmill configs.
- **`/templates/{profile_name_template_name}`**: Stores template data (including `auto_regulate` and treadmill settings).
- **`/workouts/{profile_name_start_time}`**: Stores workout summary statistics along with the nested `hr_details` map containing all heart rate logs.

---

## 🏃 Kingsmith WalkingPad BLE Protocol (GATT Specs)

The WalkingPad communication logic runs inside [treadmill_service.dart](file:///Users/rohitraghuwanshi/PythonProjects/emom-timer-flutter/lib/services/treadmill_service.dart):
- **GATT Service**: `FE00`
- **Notification Characteristic**: `FE01` (Listens for `F8 A2` status updates)
- **Write Characteristic**: `FE02` (Write-without-response)
- **Status Payloads**: Received every second when active. Byte blocks parse current speed, distance (km), running time (seconds), and step count.
- **Commands**:
  - Start belt command: `[247, 162, 4, 1, 0, 253]` (Ramps up speed)
  - Stop belt command: `[247, 162, 4, 0, 0, 253]` (Stops belt)
  - Change mode: `[247, 162, 2, mode, 0, 253]` (where `mode = 1` for Manual, `mode = 2` for Standby)
  - Adjust speed: `[247, 162, 1, speedInt, 0, 253]` (where `speedInt` is `speed * 10`)
- **CRC Checksum**: Every command is checksum-protected. The CRC calculation is `sum(bytes[1:-2]) % 256` which overrides the placeholder `0` at `bytes[length - 2]` before writing.

---

## ⌚ watchOS companion App Communication

Wrist heart rate streaming runs over Apple's native frameworks:
- **watchOS Target**: `WatchApp Watch App` target is bundled inside the Xcode workspace. Initiates a wrist `HKWorkoutSession` for high-frequency sensor updates.
- **Connectivity**: Streams BPM readings to the paired iPhone using `WCSession.default.sendMessage(["bpm": hrDouble], ...)`.
- **iOS Bridge**: [AppDelegate.swift](file:///Users/rohitraghuwanshi/PythonProjects/emom-timer-flutter/ios/Runner/AppDelegate.swift) receives the connectivity message and pipes it into the Flutter engine via the `com.chronoPulse.active/watch_hr` Method/Event Channel.
- **Dart Listener**: [watch_connectivity_service.dart](file:///Users/rohitraghuwanshi/PythonProjects/emom-timer-flutter/lib/services/watch_connectivity_service.dart) subscribes to the channel and exposes a stream of readings.

---

## 🧪 Unit Testing & Interceptor Hooks

To verify BLE treadmill routines without real hardware:
- We use `@visibleForTesting` hooks inside [treadmill_service.dart](file:///Users/rohitraghuwanshi/PythonProjects/emom-timer-flutter/lib/services/treadmill_service.dart) to mock connection state and incoming status packets.
- We capture generated commands via an `onWriteCmd` interceptor callback before the BLE writer.
- Test suites in [treadmill_service_test.dart](file:///Users/rohitraghuwanshi/PythonProjects/emom-timer-flutter/test/treadmill_service_test.dart) mock the belt states and assert the exact byte array sequences generated.

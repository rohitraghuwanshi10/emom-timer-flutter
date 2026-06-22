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

### SQLite Cache (Version 6)
- **`profiles`**: User metadata, weight presets, default sync settings, and `save_history` toggle.
- **`workout_templates`**: Name, rounds, work time, rest time, activity type, continuous mode, and template notes.
- **`workouts`**: End time, rounds completed, work/rest settings, activity type, calories, notes.
- **`heart_rate_logs`**: Chronological heartbeat records linked to workouts for graphic plotting.

### Firestore Collections
- **`/profiles/{name}`**: Holds profile presets.
- **`/templates/{profile_name_template_name}`**: Stores template data.
- **`/workouts/{profile_name_start_time}`**: Stores workout summary statistics along with the nested `hr_details` map containing all heart rate logs.

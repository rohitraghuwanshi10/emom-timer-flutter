# ChronoPulse Active (EMOM Workout Timer)

ChronoPulse Active is a sleek, modern Flutter-based EMOM (Every Minute on the Minute) workout timer designed for iOS and Android. This mobile app serves as the mobile companion to the ChronoPulse macOS desktop client, syncing seamlessly via Firebase Firestore. It features local SQLite caching, real-time Bluetooth LE heart rate monitoring, adaptive auto-regulation, Apple Health integration, and high-visibility zone training.

## 📸 Screenshots

### iPhone Companion App (Flutter)
<p align="center">
  <img src="screenshots/iPhone_Timer.png" alt="Timer Configuration" width="31%">
  &nbsp;
  <img src="screenshots/iPhone_Workout.png" alt="Active Workout HUD" width="31%">
  &nbsp;
  <img src="screenshots/iPhone_Profile.png" alt="Profile & Sync Settings" width="31%">
</p>
<p align="center">
  <img src="screenshots/iPhone_History.png" alt="Workout History & Stacked Chart" width="45%">
  &nbsp; &nbsp;
  <img src="screenshots/iPhone_Details.png" alt="Workout Details & Heart Rate Curve" width="45%">
</p>

### macOS Desktop App (Flutter)
<p align="center">
  <img src="screenshots/macOS_Main.png" alt="macOS Timer Configuration" width="48%">
  &nbsp;
  <img src="screenshots/macOS_Profile.png" alt="macOS Profile & Sync Settings" width="48%">
</p>
<p align="center">
  <img src="screenshots/macOS_History.png" alt="macOS Workout History & Stacked Chart" width="48%">
  &nbsp;
  <img src="screenshots/macOS_Details.png" alt="macOS Workout Details & Heart Rate Curve" width="48%">
</p>

---

## 📱 Features

### ⏱️ Advanced Workout Timer
- **Flexible Configuration**: Set your **Total Rounds**, **Work Duration**, and **Rest Duration** for custom workouts.
- **Open Ended Workout Mode**: Bypasses round limits so the timer runs indefinitely, looping between work and rest phases until you manually tap the Stop/End button.
- **Smart Wakelock**: Integrated screen sleep prevention keeps the screen active and visible throughout your training session.

### 🗂️ Dedicated Workout Library
- **Workout Templates**: Manage your workout templates in a dedicated Workout Library screen (`library_screen.dart`).
- **Search & Filters**: Search templates by name and filter by activity category (HIIT, Strength, Cardio, Core, Yoga, etc.) using clean scrolling choice pills.
- **Compact Layout**: Sleek, high-density row designs for templates displaying rounds, work/rest times, activity tags, and notes.
- **Quick-Start & Edit**: Tapping the play button on a card loads the template and switches to the Timer HUD instantly. Edit or delete templates with single taps.

### 🎛️ Precision Sliders & Steppers
- **Piecewise Non-linear Scale Mapping**:
  - **Work Duration**: The first 50% of the slider track maps to **10s to 5m** (5-second increments); the second 50% maps to **5m to 60m** (1-minute increments).
  - **Rest Duration**: The first 50% of the slider track maps to **0s to 2m** (5-second increments); the second 50% maps to **2m to 15m** (30-second increments).
- **Fine-Tuning Stepper Buttons**: Flanking `-` and `+` buttons next to the Work, Rest, and Rounds sliders let you adjust values precisely without dragging.
- **Header Aligned Labels**: Displays parameter names on the left and beautifully formatted values (e.g. `2m 30s`, `None`, `15`) on the right.

### ❤️ Heart Rate Intelligence & Zone Training
- **Bluetooth LE Integration**: Connect standard heart rate monitors (e.g., Polar H10, Garmin, etc.) with automatic background scanning and reconnection.
- **High-Visibility HUD**: Large heart rate and zone indicator (Zone 1 to 5) styled with a pulsing neon micro-animation for quick glance updates during high-intensity intervals.
- **Auto-Regulation (Smart Rest)**: Pause and hold the rest phase countdown if your heart rate is above your profile's configured threshold, ensuring you recover before the next round begins.
- **Calorie Estimation**: Dynamic real-time calorie burn tracking using sex, age, weight, and average heart rate intensity.

### 🍏 Apple Health (HealthKit) Integration (iOS)
- **Automatic Health Log**: Write completed workouts, active calories burned, and chronological heart rate logs directly to Apple Health on iOS devices.
- **Biological Characteristics Retrieval**: Automatically imports user biological sex, birth date, and weight from Apple Health to populate active profiles and refine zone/calorie equations.
- **Activity Category Mapping**: Maps selected workout types (HIIT, Strength, Cardio, Yoga, etc.) directly to Apple HealthKit activity enums.

### 🔄 Bidirectional Firebase Sync
- **Local SQLite Cache**: Workouts are logged first to local SQLite databases using cross-platform `sqflite` (with FFI support).
- **Background Sync**: Silent, anonymous authentication syncing profiles, workout templates, and detailed logs automatically to Cloud Firestore.
- **Resilient Offline Work**: Perform workouts offline and sync changes immediately once internet connection is restored.
- **Notes Editor**: Tap notes in the workout history list to edit them. Edits update the local database and synchronize automatically to Firebase.
- **Profile-Level "Save History"**: Control whether workouts are logged to the database on a per-profile basis.

### 👤 AppBar Capsule Profile Selector
- **Global Selector**: Replaced bulky body-level selectors with a sleek, pill-shaped capsule profile selector in the AppBar of every screen.
- **Real-Time Synchronization**: Instantly synchronizes active profile switches across all tabs in real-time.
- **Workout Safety**: Automatically disables profile switches during active workouts to prevent data mixing.

### 📊 History & Analytics
- **Stacked Progress Graph**: A 7-day visual history chart detailing daily completed workouts.
- **Nord-Themed Intensity Zones**: Line charts visualize heart rate curves mapped directly to your training zones.
- **CSV Exporter**: Single-tap export of the day's workouts directly to your device storage in a clean, standard CSV format.

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

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: `>=3.0.0`
- **CocoaPods** (for iOS builds)
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
   - For iOS: Place your `GoogleService-Info.plist` in the `ios/Runner` folder and link it via Xcode.
   - For Android: Place your `google-services.json` in `android/app`.

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

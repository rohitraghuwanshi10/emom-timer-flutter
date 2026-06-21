import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'dart:io' show Platform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (Platform.isIOS || Platform.isMacOS) {
      return ios;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not configured for this platform.',
    );
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD5eDqh70ZNN9KQ8DMaPYEaeCZ4d6wlu1Q',
    appId: '1:484430383783:ios:96b3cba5ff1a3a5eba6982',
    messagingSenderId: '484430383783',
    projectId: 'emom-timer-sync',
    storageBucket: 'emom-timer-sync.firebasestorage.app',
    iosBundleId: 'com.rohitraghuwanshi.emomTimerFlutter',
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/services/sync_service.dart';

void main() {
  group('SyncService when signed out', () {
    late bool firestoreTouched;

    setUp(() {
      firestoreTouched = false;
      SyncService.instance.isSignedInOverride = () => false;
      SyncService.instance.firestoreFactoryOverride = () {
        firestoreTouched = true;
        throw StateError('Firestore must not be accessed while signed out');
      };
    });

    test('signInAndSync returns false without touching Firestore', () async {
      var notified = 0;
      void listener() => notified++;
      SyncService.instance.addListener(listener);

      final result = await SyncService.instance.signInAndSync();

      SyncService.instance.removeListener(listener);
      expect(result, isFalse);
      expect(SyncService.instance.syncStatus, 'Signed out');
      expect(SyncService.instance.lastError, 'Sign in to enable cloud sync.');
      expect(SyncService.instance.isSyncing, isFalse);
      expect(notified, greaterThan(0));
      expect(firestoreTouched, isFalse);
    });

    test('deleteTemplateRemote is a no-op', () async {
      await SyncService.instance.deleteTemplateRemote('Default', 'Tabata');
      expect(firestoreTouched, isFalse);
    });
  });
}

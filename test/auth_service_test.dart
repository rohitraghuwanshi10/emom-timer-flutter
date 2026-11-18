import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/services/auth_service.dart';

class FakeAuthBackend implements AuthBackend {
  FakeAuthBackend({this.user});

  AuthUser? user;
  int signOutCalls = 0;
  String? lastEmail;
  String? lastPassword;
  FirebaseAuthException? signInError;
  AuthUser signInResult = const AuthUser(
    isAnonymous: false,
    email: 'home@example.com',
  );
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  bool hang = false;

  @override
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    lastEmail = email;
    lastPassword = password;
    if (hang) return Completer<void>().future;
    if (signInError != null) throw signInError!;
    user = signInResult;
    _controller.add(user);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    user = null;
    _controller.add(null);
  }
}

void main() {
  group('AuthService', () {
    test('init() signs out a leftover anonymous user', () async {
      final backend = FakeAuthBackend(user: const AuthUser(isAnonymous: true));
      final auth = AuthService.forTesting(backend);
      await auth.init();
      expect(backend.signOutCalls, 1);
      expect(auth.isSignedIn, isFalse);
    });

    test('init() keeps a non-anonymous user signed in', () async {
      final backend = FakeAuthBackend(
        user: const AuthUser(isAnonymous: false, email: 'home@example.com'),
      );
      final auth = AuthService.forTesting(backend);
      await auth.init();
      expect(backend.signOutCalls, 0);
      expect(auth.isSignedIn, isTrue);
      expect(auth.email, 'home@example.com');
    });

    test('isSignedIn is false for an anonymous user', () async {
      final backend = FakeAuthBackend();
      final auth = AuthService.forTesting(backend);
      await auth.init();
      // Anonymous user appearing after init(): the getter itself must reject it.
      backend.user = const AuthUser(isAnonymous: true);
      expect(auth.isSignedIn, isFalse);
    });

    test('isSignedIn is false with no user', () async {
      final auth = AuthService.forTesting(FakeAuthBackend());
      await auth.init();
      expect(auth.isSignedIn, isFalse);
      expect(auth.email, isNull);
    });

    test('signIn trims email, succeeds and notifies listeners', () async {
      final backend = FakeAuthBackend();
      final auth = AuthService.forTesting(backend);
      await auth.init();
      var notified = 0;
      auth.addListener(() => notified++);

      final result = await auth.signIn('  home@example.com  ', 'pw');
      expect(result, isNull);
      expect(backend.lastEmail, 'home@example.com');
      expect(backend.lastPassword, 'pw');
      expect(auth.isSignedIn, isTrue);
      expect(notified, greaterThan(0));
    });

    test('signOut clears the session', () async {
      final backend = FakeAuthBackend(
        user: const AuthUser(isAnonymous: false, email: 'home@example.com'),
      );
      final auth = AuthService.forTesting(backend);
      await auth.init();
      await auth.signOut();
      expect(auth.isSignedIn, isFalse);
    });

    const expected = {
      'invalid-credential': 'Incorrect email or password.',
      'wrong-password': 'Incorrect email or password.',
      'user-not-found': 'Incorrect email or password.',
      'invalid-email': 'Incorrect email or password.',
      'too-many-requests': 'Too many attempts. Try again later.',
      'network-request-failed': 'No internet connection.',
      'keychain-error':
          "Keychain access failed. Check the app's keychain entitlement.",
      'operation-not-allowed': 'Sign-in failed (operation-not-allowed).',
    };

    for (final entry in expected.entries) {
      test('signIn maps ${entry.key}', () async {
        final backend = FakeAuthBackend()
          ..signInError = FirebaseAuthException(code: entry.key);
        final auth = AuthService.forTesting(backend);
        await auth.init();
        expect(await auth.signIn('home@example.com', 'pw'), entry.value);
        expect(auth.isSignedIn, isFalse);
      });
    }

    test('signIn times out instead of hanging', () async {
      final backend = FakeAuthBackend()..hang = true;
      final auth = AuthService.forTesting(backend)
        ..signInTimeout = const Duration(milliseconds: 50);
      await auth.init();
      expect(
        await auth.signIn('home@example.com', 'pw'),
        'Sign-in timed out. Check your internet connection.',
      );
      expect(auth.isSignedIn, isFalse);
    });
  });
}

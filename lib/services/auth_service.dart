import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Minimal view of a signed-in user, decoupled from the Firebase plugin.
class AuthUser {
  final bool isAnonymous;
  final String? email;
  const AuthUser({required this.isAnonymous, this.email});
}

/// Small injectable interface over FirebaseAuth so [AuthService] can be
/// unit-tested without platform plugins.
abstract class AuthBackend {
  AuthUser? get currentUser;
  Stream<AuthUser?> authStateChanges();
  Future<void> signInWithEmailAndPassword(String email, String password);
  Future<void> signOut();
}

class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  static AuthUser? _map(User? user) => user == null
      ? null
      : AuthUser(isAnonymous: user.isAnonymous, email: user.email);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  Future<void> signInWithEmailAndPassword(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> signOut() => _auth.signOut();
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._(FirebaseAuthBackend());

  final AuthBackend _backend;
  StreamSubscription<AuthUser?>? _sub;
  bool _ready = false;

  AuthService._(this._backend);

  @visibleForTesting
  Duration signInTimeout = const Duration(seconds: 15);

  @visibleForTesting
  AuthService.forTesting(this._backend);

  AuthUser? get _user => _ready ? _backend.currentUser : null;

  /// True only for a real (non-anonymous) account.
  bool get isSignedIn {
    final user = _user;
    return user != null && !user.isAnonymous;
  }

  String? get email => _user?.email;

  Future<void> init() async {
    await _sub?.cancel();
    _sub = _backend.authStateChanges().listen((_) => notifyListeners());
    _ready = true;
    // Anonymous sessions left over from older builds are no longer authorized.
    if (_backend.currentUser?.isAnonymous ?? false) {
      debugPrint('AuthService: Signing out leftover anonymous session.');
      await _backend.signOut();
    }
    notifyListeners();
  }

  /// Returns null on success, otherwise a short user-facing message.
  Future<String?> signIn(String email, String password) async {
    try {
      await _backend
          .signInWithEmailAndPassword(email.trim(), password)
          .timeout(signInTimeout);
      notifyListeners();
      return null;
    } on TimeoutException {
      debugPrint('AuthService: Sign-in timed out.');
      return 'Sign-in timed out. Check your internet connection.';
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: Sign-in failed (${e.code}).');
      return messageForCode(e.code);
    } catch (e) {
      debugPrint('AuthService: Sign-in failed: ${e.runtimeType}');
      return 'Sign-in failed.';
    }
  }

  Future<void> signOut() async {
    await _backend.signOut();
    notifyListeners();
  }

  @visibleForTesting
  static String messageForCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'keychain-error':
        return "Keychain access failed. Check the app's keychain entitlement.";
      default:
        return 'Sign-in failed ($code).';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

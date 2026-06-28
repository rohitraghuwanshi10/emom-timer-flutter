import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class WatchConnectivityService {
  static const EventChannel _watchEventChannel =
      EventChannel('com.chronoPulse.active/watch_hr');

  static final WatchConnectivityService instance = WatchConnectivityService._();
  WatchConnectivityService._();

  final StreamController<int> _hrController = StreamController<int>.broadcast();
  Stream<int> get heartRateStream => _hrController.stream;

  StreamSubscription? _subscription;

  void startListening() {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return;
    }
    _subscription?.cancel();
    _subscription = _watchEventChannel.receiveBroadcastStream().listen(
      (dynamic bpm) {
        if (bpm is int && bpm > 0) {
          _hrController.add(bpm);
        }
      },
      onError: (dynamic err) {
        // Log connectivity/parsing errors silently to prevent console pollution
      },
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}

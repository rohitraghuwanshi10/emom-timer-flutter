import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService instance = AudioService._init();
  late final AudioPlayer _workPlayer;
  late final AudioPlayer _restPlayer;

  AudioService._init() {
    _workPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _restPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _configureAudioSession();
    
    // Preload assets natively to buffer
    _workPlayer.setReleaseMode(ReleaseMode.stop);
    _workPlayer.setSource(AssetSource('sounds/Glass.wav'));

    _restPlayer.setReleaseMode(ReleaseMode.stop);
    _restPlayer.setSource(AssetSource('sounds/Hero.wav'));
  }

  void _configureAudioSession() async {
    // Configure audio context to duck other sounds (e.g. Spotify) instead of pausing them
    final ctx = AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient, // ambient allows mixing
        options: {
          AVAudioSessionOptions.duckOthers,
          AVAudioSessionOptions.mixWithOthers,
        },
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    );
    await _workPlayer.setAudioContext(ctx);
    await _restPlayer.setAudioContext(ctx);
  }

  Future<void> playWorkChime() async {
    await _workPlayer.stop();
    await _workPlayer.resume();
  }

  Future<void> playRestChime() async {
    await _restPlayer.stop();
    await _restPlayer.resume();
  }
  
  Future<void> dispose() async {
    await _workPlayer.dispose();
    await _restPlayer.dispose();
  }
}

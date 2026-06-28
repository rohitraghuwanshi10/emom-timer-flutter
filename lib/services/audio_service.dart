import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService instance = AudioService._init();
  late final AudioPlayer _workPlayer;
  late final AudioPlayer _restPlayer;
  late final AudioPlayer _tickPlayer;

  AudioService._init() {
    _workPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _restPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _tickPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _configureAudioSession();
    
    // Preload assets natively to buffer
    _workPlayer.setReleaseMode(ReleaseMode.stop);
    _workPlayer.setSource(AssetSource('sounds/Glass.wav'));

    _restPlayer.setReleaseMode(ReleaseMode.stop);
    _restPlayer.setSource(AssetSource('sounds/Hero.wav'));

    _tickPlayer.setReleaseMode(ReleaseMode.stop);
    _tickPlayer.setSource(AssetSource('sounds/Glass.wav'));
    _tickPlayer.setVolume(0.5);
    _tickPlayer.setPlaybackRate(2.4); // High-pitched short tink for countdown ticks
  }

  void _configureAudioSession() async {
    // Configure audio context to duck other sounds (e.g. Spotify) instead of pausing them
    final ctx = AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback, // playback allows explicit mixing & ducking
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
    await _tickPlayer.setAudioContext(ctx);
  }

  Future<void> playWorkChime() async {
    await _workPlayer.stop();
    await _workPlayer.resume();
  }

  Future<void> playRestChime() async {
    await _restPlayer.stop();
    await _restPlayer.resume();
  }

  Future<void> playTick() async {
    await _tickPlayer.stop();
    await _tickPlayer.resume();
  }
  
  Future<void> dispose() async {
    await _workPlayer.dispose();
    await _restPlayer.dispose();
    await _tickPlayer.dispose();
  }
}

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService instance = AudioService._init();
  late final AudioPlayer _player;

  AudioService._init() {
    _player = AudioPlayer();
    _configureAudioSession();
  }

  void _configureAudioSession() async {
    // Configure audio context to duck other sounds (e.g. Spotify) instead of pausing them
    await _player.setAudioContext(AudioContext(
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
    ));
  }

  Future<void> playWorkChime() async {
    await _player.play(AssetSource('sounds/Glass.wav'));
  }

  Future<void> playRestChime() async {
    await _player.play(AssetSource('sounds/Hero.wav'));
  }
  
  Future<void> dispose() async {
    await _player.dispose();
  }
}

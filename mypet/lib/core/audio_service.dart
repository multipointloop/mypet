import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Silent-fail audio wrapper: a missing / broken / unloaded sound file must
/// never crash the pet or pop a dialog - it is simply skipped. Users can drop
/// real mp3/wav files into assets/sounds/ later and rebuild (or hot-replace
/// in debug) without touching any code.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final Map<String, AudioPlayer> _players = {};
  final Set<String> _missing = {};
  bool enabled = true;
  double volume = 0.8;

  static const _known = [
    'click_head', 'click_body', 'click_tail', 'land', 'surprise', 'key', 'mew',
  ];

  Future<void> preload() async {
    for (final name in _known) {
      try {
        await rootBundle.load('assets/sounds/$name.wav');
      } catch (_) {
        _missing.add(name);
      }
    }
  }

  Future<void> play(String name) async {
    if (!enabled || _missing.contains(name)) return;
    try {
      final player = _players.putIfAbsent(name, AudioPlayer.new);
      await player.setVolume(volume);
      // stop() first so repeated taps retrigger from the start
      await player.stop();
      await player.play(AssetSource('sounds/$name.wav'));
    } catch (e) {
      // missing/corrupt asset or device without audio - stay silent
      _missing.add(name);
    }
  }
}

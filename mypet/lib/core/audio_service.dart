import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// 静默容错音频 + 声部池（voice pool）。
///
/// * 每个音效预建若干 [AudioPlayer] 轮转使用：高频连击时不会互相打断/丢音；
/// * 每个声部只在首次播放时 setSource，之后走 seek(0)+resume()，
///   避免每次敲键都重新读资源（这是极限连击掉帧的主因）；
/// * 任何失败静默降级，缺失音效拉黑不再重试。
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const int _voices = 4;

  final Map<String, List<AudioPlayer>> _pools = {};
  final Map<String, int> _next = {};
  final Set<AudioPlayer> _primed = {};
  final Set<String> _missing = {};

  bool enabled = true;

  double _volume = 0.8;
  double get volume => _volume;
  set volume(double v) {
    _volume = v;
    for (final pool in _pools.values) {
      for (final p in pool) {
        p.setVolume(v);
      }
    }
  }

  /// 音效名 -> 资源文件（wav / mp3 混用；文件名保持 ASCII，避免中文路径问题）
  static const Map<String, String> _files = {
    'click_head': 'bounce.mp3',
    'bounce': 'bounce.mp3',
    'click_body': 'click_body.wav',
    'click_tail': 'click_tail.wav',
    'land': 'land.wav',
    'surprise': 'surprise.wav',
    'key': 'key.wav',
    'mew': 'mew.wav',
    'charge': 'charge.wav',
    'swoosh': 'swoosh.wav',
  };

  static String _asset(String name) => _files[name] ?? '$name.wav';

  Future<void> preload() async {
    for (final entry in _files.entries) {
      try {
        await rootBundle.load('assets/sounds/${entry.value}');
      } catch (_) {
        _missing.add(entry.key);
      }
    }
  }

  Future<void> play(String name) async {
    if (!enabled || _missing.contains(name)) return;
    try {
      final pool = _pools.putIfAbsent(
          name, () => List<AudioPlayer>.generate(_voices, (_) => AudioPlayer()));
      final i = (_next[name] ?? 0) % _voices;
      _next[name] = i + 1;
      final player = pool[i];
      if (!_primed.contains(player)) {
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(_volume);
        await player.setSource(AssetSource('sounds/${_asset(name)}'));
        _primed.add(player);
      }
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {
      _missing.add(name);
    }
  }
}
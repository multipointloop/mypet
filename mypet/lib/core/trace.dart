import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 轻量诊断日志：写入应用专属数据目录，滚动切割（单文件 2MB，最多 5 个文件）。
///
/// * 目录由 path_provider 解析，flutter clean / 换机后依然有效（不再硬编码 E: 盘）；
/// * 可在设置页整体关闭（默认开启）；
/// * 异步批量落盘，永不阻塞 UI；任何写入失败一律静默。
class Trace {
  Trace._();

  static const int _maxBytes = 2 * 1024 * 1024;
  static const int _maxFiles = 5;
  static const String _fileName = 'mypet.log';

  static bool _enabled = true;
  static bool get enabled => _enabled;
  static set enabled(bool value) {
    _enabled = value;
    if (value) log('trace enabled');
  }

  static Directory? _dir;
  static File? _file;
  static int _size = 0;
  static final List<String> _pending = [];
  static bool _writing = false;

  static Directory? get logDir => _dir;

  /// 解析日志目录（应用专属数据目录下的 logs/）。
  static Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      _file = File(_path(dir, _fileName));
      _size = _file!.existsSync() ? _file!.lengthSync() : 0;
    } catch (_) {
      _dir = null;
      _file = null;
    }
  }

  static void log(String msg) {
    if (!_enabled || _file == null) return;
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    _pending.add('$stamp $msg');
    if (_pending.length > 256) {
      _pending.removeRange(0, _pending.length - 256);
    }
    if (!_writing) _drain();
  }

  static Future<void> _drain() async {
    _writing = true;
    try {
      while (_pending.isNotEmpty) {
        final f = _file;
        if (f == null) {
          _pending.clear();
          return;
        }
        final bytes = utf8.encode('${_pending.removeAt(0)}\n');
        await f.writeAsBytes(bytes, mode: FileMode.append, flush: false);
        _size += bytes.length;
        if (_size >= _maxBytes) await _rotate();
      }
    } catch (_) {
      _pending.clear();
    } finally {
      _writing = false;
    }
  }

  /// mypet.log -> mypet.log.1 -> ... -> mypet.log.4；超出 _maxFiles 丢弃最旧。
  static Future<void> _rotate() async {
    final d = _dir;
    final f = _file;
    if (d == null || f == null) return;
    try {
      final oldest = File(_path(d, '$_fileName.${_maxFiles - 1}'));
      if (oldest.existsSync()) oldest.deleteSync();
      for (var i = _maxFiles - 2; i >= 1; i--) {
        final src = File(_path(d, '$_fileName.$i'));
        if (src.existsSync()) {
          src.renameSync(_path(d, '$_fileName.${i + 1}'));
        }
      }
      if (f.existsSync()) f.renameSync(_path(d, '$_fileName.1'));
      _size = 0;
    } catch (_) {}
  }

  static String _path(Directory d, String name) =>
      '${d.path}${Platform.pathSeparator}$name';

  /// 在资源管理器中打开日志目录。
  static Future<void> openLogDir() async {
    final d = _dir;
    if (d == null || !Platform.isWindows) return;
    try {
      await Process.run('explorer', [d.path]);
    } catch (_) {}
  }
}

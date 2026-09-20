import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/win/window_service.dart';
import 'audio_service.dart';
import 'trace.dart';

/// All user-facing settings, persisted via SharedPreferences and mirrored to
/// the platform services (window size, click-through, tray menu state...).
class Config extends ChangeNotifier {
  Config._();
  static final Config instance = Config._();

  static const _kScale = 'petScale';
  static const _kClickThrough = 'clickThrough';
  static const _kBongoHook = 'bongoHook'; // default OFF (AV / anti-cheat safety)
  static const _kDialogue = 'dialogue';
  static const _kSound = 'sound';
  static const _kVolume = 'volume';
  static const _kAutostart = 'autostart';
  static const _kIdleBlink = 'idleBlink';
  static const _kNormalOpacity = 'normalOpacity';
  static const _kClickThroughOpacity = 'clickThroughOpacity';
  static const _kGravityFall = 'gravityFall';
  static const _kDiagnostics = 'diagnostics';
  static const _kDialogueLines = 'dialogueLines';

  SharedPreferences? _sp;
  bool _loaded = false;

  // current values (defaults before prefs load)
  double petScale = 1.0;
  bool clickThrough = false;
  bool bongoHook = false;
  bool dialogue = true;
  bool sound = true;
  double volume = 0.8;
  bool autostart = false;
  bool idleBlink = true;
  double normalOpacity = 1.0;
  double clickThroughOpacity = 0.55;
  bool gravityFall = false; // off: pet stays where dropped (free vertical)
  bool diagnostics = true; // 诊断日志开关（默认开启）

  /// 用户自定义台词：key -> 台词列表（每行一条）。空/缺失 = 用内置默认。
  Map<String, List<String>> dialogueLines = {};

  Future<void> load() async {
    if (_loaded) return;
    _sp = await SharedPreferences.getInstance();
    final sp = _sp!;
    petScale = sp.getDouble(_kScale) ?? 1.0;
    // passthrough is a SESSION mode (like a flashlight): always start
    // interactive, otherwise a forgotten toggle makes the pet look frozen
    clickThrough = false;
    bongoHook = sp.getBool(_kBongoHook) ?? false;
    dialogue = sp.getBool(_kDialogue) ?? true;
    sound = sp.getBool(_kSound) ?? true;
    volume = sp.getDouble(_kVolume) ?? 0.8;
    autostart = sp.getBool(_kAutostart) ?? false;
    idleBlink = sp.getBool(_kIdleBlink) ?? true;
    normalOpacity = sp.getDouble(_kNormalOpacity) ?? 1.0;
    clickThroughOpacity = sp.getDouble(_kClickThroughOpacity) ?? 0.55;
    gravityFall = sp.getBool(_kGravityFall) ?? false;
    diagnostics = sp.getBool(_kDiagnostics) ?? true;
    final rawLines = sp.getString(_kDialogueLines);
    if (rawLines != null) {
      try {
        final decoded = jsonDecode(rawLines) as Map<String, dynamic>;
        dialogueLines = decoded.map((k, v) => MapEntry(
            k, (v as List).map((e) => e.toString()).toList()));
      } catch (_) {
        dialogueLines = {};
      }
    }
    _loaded = true;
    Trace.enabled = diagnostics;
  }

  Future<void> _save(String key, Object value) async {
    if (value is bool) {
      await _sp?.setBool(key, value);
    } else if (value is double) {
      await _sp?.setDouble(key, value);
    } else if (value is int) {
      await _sp?.setInt(key, value);
    } else {
      await _sp?.setString(key, value.toString());
    }
  }

  set petScaleValue(double v) {
    petScale = v.clamp(0.35, 2.5);
    _save(_kScale, petScale);
    notifyListeners();
  }

  void _set(String key, Object value) {
    switch (key) {
      case _kScale:
        petScale = (value as num).toDouble().clamp(0.35, 2.5);
      case _kClickThrough:
        clickThrough = value as bool;
      case _kBongoHook:
        bongoHook = value as bool;
      case _kDialogue:
        dialogue = value as bool;
      case _kSound:
        sound = value as bool;
      case _kVolume:
        volume = (value as num).toDouble();
      case _kAutostart:
        autostart = value as bool;
      case _kIdleBlink:
        idleBlink = value as bool;
      case _kNormalOpacity:
        normalOpacity = (value as num).toDouble().clamp(0.30, 1.0);
      case _kClickThroughOpacity:
        clickThroughOpacity = (value as num).toDouble().clamp(0.10, 1.0);
      case _kGravityFall:
        gravityFall = value as bool;
      case _kDiagnostics:
        diagnostics = value as bool;
        Trace.enabled = diagnostics;
    }
    _save(key, value);
    notifyListeners();
  }

  void setClickThrough(bool v) => _set(_kClickThrough, v);
  void setBongoHook(bool v) => _set(_kBongoHook, v);
  void setDialogue(bool v) => _set(_kDialogue, v);
  void setSound(bool v) => _set(_kSound, v);
  void setVolume(double v) => _set(_kVolume, v);
  void setAutostart(bool v) => _set(_kAutostart, v);
  void setIdleBlink(bool v) => _set(_kIdleBlink, v);
  void setNormalOpacity(double v) => _set(_kNormalOpacity, v);
  void setClickThroughOpacity(double v) => _set(_kClickThroughOpacity, v);
  void setGravityFall(bool v) => _set(_kGravityFall, v);
  void setDiagnostics(bool v) => _set(_kDiagnostics, v);
  void setScale(double v) => _set(_kScale, v);

  /// 保存用户自定义台词（空列表 = 该键恢复内置默认）。
  Future<void> setDialogueLines(Map<String, List<String>> lines) async {
    dialogueLines = lines;
    await _sp?.setString(_kDialogueLines, jsonEncode(lines));
    notifyListeners();
  }

  /// Push the current settings down into the platform services.
  /// 尺寸不在这里处理：窗口几何必须由调用方显式 resize 一次，
  /// 否则同一次变更会产生并发 SetWindowPos（历史崩溃点）。
  Future<void> applyToPlatform() async {
    AudioService.instance.enabled = sound;
    AudioService.instance.volume = volume;
    if (Platform.isWindows) {
      final win = WindowsWindowService.instance;
      await win.setClickThrough(clickThrough);
      await win.setOpacity(clickThrough ? clickThroughOpacity : normalOpacity);
      await win.setBongoHook(bongoHook);
      await win.setAutostart(autostart);
    }
  }
}

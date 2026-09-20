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
    _loaded = true;
  }

  /// Re-read persisted values (used by the separate settings window engine,
  /// which saves prefs and then pings the pet engine to reload them).
  Future<void> reload() async {
    _loaded = false;
    await load();
    notifyListeners();
  }

  /// Called once per second by the pet engine: pick up changes that the
  /// settings window wrote to the shared prefs file. All window-manager
  /// operations stay on the PET engine (calling them from the settings
  /// window engine crashes the process).
  Future<void> syncIfChanged() async {
    if (!_loaded) return;
    final sp = _sp;
    if (sp == null) return;
    try {
      await sp.reload();
    } catch (_) {
      return;
    }
    var changed = false;
    void chkDouble(String k, double cur, void Function(double) set) {
      final v = sp.getDouble(k);
      if (v != null && v != cur) {
        set(v);
        changed = true;
      }
    }

    void chkBool(String k, bool cur, void Function(bool) set) {
      final v = sp.getBool(k);
      if (v != null && v != cur) {
        set(v);
        changed = true;
      }
    }

    chkDouble(_kScale, petScale, setScale);
    chkDouble(_kNormalOpacity, normalOpacity, setNormalOpacity);
    chkDouble(_kClickThroughOpacity, clickThroughOpacity,
        setClickThroughOpacity);
    chkDouble(_kVolume, volume, setVolume);
    chkBool(_kClickThrough, clickThrough, setClickThrough);
    chkBool(_kBongoHook, bongoHook, setBongoHook);
    chkBool(_kDialogue, dialogue, setDialogue);
    chkBool(_kSound, sound, setSound);
    chkBool(_kAutostart, autostart, setAutostart);
    chkBool(_kIdleBlink, idleBlink, setIdleBlink);
    chkBool(_kGravityFall, gravityFall, setGravityFall);
    Trace.log('syncIfChanged changed=$changed');
    if (changed) {
      Trace.log('syncIfChanged notifying listeners');
      notifyListeners();
      Trace.log('syncIfChanged notified');
    }
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
  void setScale(double v) => _set(_kScale, v);

  /// Push the current settings down into the platform services.
  Future<void> applyToPlatform() async {
    AudioService.instance.enabled = sound;
    AudioService.instance.volume = volume;
    if (Platform.isWindows) {
      final win = WindowsWindowService.instance;
      await win.setClickThrough(clickThrough);
      await win.setOpacity(clickThrough ? clickThroughOpacity : normalOpacity);
      await win.resizeToPet(petScale);
      await win.setBongoHook(bongoHook);
      await win.setAutostart(autostart);
    }
  }
}

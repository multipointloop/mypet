import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart' show MethodChannel;

import '../../core/config.dart';
import '../../platform/android/overlay_service.dart';

/// Independent settings window (desktop_multi_window) - fixed size, fully
/// decoupled from the pet window, so it never scales or gets clipped.
class SettingsWindowApp extends StatelessWidget {
  const SettingsWindowApp({super.key, required this.windowId});

  final int windowId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyPet 设置',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: ['Microsoft YaHei', 'SimHei', 'PingFang SC'],
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8AB5),
          brightness: Brightness.light,
        ),
      ),
      home: _SettingsWindowPage(windowId: windowId),
    );
  }
}

class _SettingsWindowPage extends StatefulWidget {
  const _SettingsWindowPage({required this.windowId});

  final int windowId;

  @override
  State<_SettingsWindowPage> createState() => _SettingsWindowPageState();
}

class _SettingsWindowPageState extends State<_SettingsWindowPage> {
  /// Changes are saved only; the pet engine picks them up within a second.
  Future<void> _changed([Future<void> Function()? extra]) async {
    if (extra != null) await extra();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cfg = Config.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyPet 设置'),
        actions: [
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () =>
                WindowController.fromWindowId(widget.windowId).close(),
          ),
        ],
      ),
      body: FutureBuilder(
        future: cfg.load(),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _section(context, '外观', [
                _slider(context, '尺寸', cfg.petScale, 0.35, 2.5,
                    (v) => _changed(() async => cfg.setScale(v))),
                _slider(context, '常态透明度', cfg.normalOpacity, 0.3, 1,
                    (v) => _changed(() async => cfg.setNormalOpacity(v))),
                _slider(context, '穿透时透明度', cfg.clickThroughOpacity, 0.1, 1,
                    (v) => _changed(() async => cfg.setClickThroughOpacity(v))),
              ]),
              _section(context, '交互', [
                _switch('鼠标穿透（背景直接放行）', cfg.clickThrough, (v) {
                  cfg.setClickThrough(v);
                  return _changed();
                },
                    subtitle:
                        '宠物半透明且不可点，右上角小眼睛按钮始终可点，随时恢复'),
                _switch('松手重力下落', cfg.gravityFall, (v) {
                  cfg.setGravityFall(v);
                  return _changed();
                },
                    subtitle: '关闭时拖到哪里就停在哪里'),
                _switch('键盘互动 Bongo Cat', cfg.bongoHook, (v) {
                  cfg.setBongoHook(v);
                  return _changed();
                },
                    subtitle: '默认关闭 · 全局键盘钩子，可能触发杀软提示，游戏时建议关闭'),
              ]),
              _section(context, '氛围', [
                _switch('闲置台词气泡', cfg.dialogue, (v) {
                  cfg.setDialogue(v);
                  return _changed();
                }),
                _switch('音效', cfg.sound, (v) {
                  cfg.setSound(v);
                  return _changed();
                }),
                _slider(context, '音量', cfg.volume, 0, 1,
                    (v) => _changed(() async => cfg.setVolume(v))),
                _switch('随机眨眼', cfg.idleBlink, (v) {
                  cfg.setIdleBlink(v);
                  return _changed();
                }),
              ]),
              _section(context, '系统', [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开机自启'),
                  value: cfg.autostart,
                  onChanged: (v) {
                    cfg.setAutostart(v);
                    _changed();
                  },
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB0567A))),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _slider(BuildContext context, String label, double value, double min,
      double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('$label  ${value.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12.5)),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min) >= 1 ? ((max - min) * 100).round() : 70,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _switch(String label, bool value,
      Future<void> Function(bool) onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
      value: value,
      onChanged: (v) => onChanged(v),
    );
  }
}

/// Android main-activity settings page (permissions, overlay control...).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool overlayRunning = false;
  bool permission = false;
  static const _keepAlive = MethodChannel('mypet/keepalive');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    permission = await OverlayService.isPermissionGranted();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cfg = Config.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('MyPet 桌宠设置')),
      body: FutureBuilder(
        future: cfg.load(),
        builder: (context, _) {
          final petW = 260 * cfg.petScale;
          final petH = 360 * cfg.petScale;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(context, icons: Icons.layers, title: '悬浮窗桌宠', children: [
                ListTile(
                  leading: Icon(permission ? Icons.check_circle : Icons.error,
                      color: permission ? Colors.green : Colors.red),
                  title: const Text('悬浮窗权限（其他应用上层显示）'),
                  subtitle: const Text('显示桌宠悬浮窗所必需的系统权限'),
                  trailing: FilledButton(
                    onPressed: () async {
                      if (!permission) await OverlayService.requestPermission();
                      await _refresh();
                    },
                    child: Text(permission ? '已授权' : '去授权'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.battery_saver),
                  title: const Text('跳过电池优化（后台保活）'),
                  subtitle: const Text('防止悬浮窗被系统回收；国产 ROM 还需在设置中允许自启动'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _keepAlive
                        .invokeMethod('requestIgnoreBatteryOptimization'),
                    child: const Text('设置'),
                  ),
                ),
                FilledButton.icon(
                  icon: Icon(overlayRunning ? Icons.close : Icons.pets),
                  label: Text(overlayRunning ? '关闭桌宠悬浮窗' : '启动桌宠悬浮窗'),
                  onPressed: () async {
                    if (overlayRunning) {
                      await OverlayService.close();
                      overlayRunning = false;
                    } else {
                      await OverlayService.show(petW: petW, petH: petH);
                      overlayRunning = true;
                    }
                    setState(() {});
                  },
                ),
              ]),
              _card(context, icons: Icons.tune, title: '外观与交互', children: [
                StatefulBuilder(builder: (context, setLocal) {
                  return Column(
                    children: [
                      ListTile(
                        title: const Text('尺寸'),
                        subtitle: Slider(
                          value: cfg.petScale.clamp(0.35, 2.5),
                          min: 0.35,
                          max: 2.5,
                          divisions: 43,
                          label: cfg.petScale.toStringAsFixed(2),
                          onChanged: (v) {
                            cfg.setScale(v);
                            OverlayService.send({'cmd': 'scale', 'v': v});
                            setLocal(() {});
                          },
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('闲置台词气泡'),
                        value: cfg.dialogue,
                        onChanged: (v) {
                          cfg.setDialogue(v);
                          setLocal(() {});
                        },
                      ),
                      SwitchListTile(
                        title: const Text('音效'),
                        value: cfg.sound,
                        onChanged: (v) {
                          cfg.setSound(v);
                          setLocal(() {});
                        },
                      ),
                      SwitchListTile(
                        title: const Text('随机眨眼'),
                        value: cfg.idleBlink,
                        onChanged: (v) {
                          cfg.setIdleBlink(v);
                          setLocal(() {});
                        },
                      ),
                    ],
                  );
                }),
              ]),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '提示：MIUI / EMUI / ColorOS 等系统需在"设置-应用管理-MyPet"中开启\n'
                  '① 自启动 ② 后台弹出界面 ③ 显示悬浮窗 ④ 电池无限制，桌宠才能常驻。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context,
      {required IconData icons,
      required String title,
      required List<Widget> children}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Icon(icons,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

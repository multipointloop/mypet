import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../../core/config.dart';
import '../../platform/android/overlay_service.dart';


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

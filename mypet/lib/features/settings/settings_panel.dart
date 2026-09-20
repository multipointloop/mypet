import 'package:flutter/material.dart';

import '../../core/config.dart';

/// Windows 设置面板：直接嵌在宠物窗口内渲染，不再另开引擎/窗口。
///
/// * 面板自己绘制不透明底色（宠物窗口本身保持透明 + 不做 DWM 重设）；
/// * 所有控件操作的是同一个 [Config] 实例，无需跨引擎轮询；
/// * 窗口形态切换由 WindowsWindowService 负责，本 widget 只管 UI。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.onClose,
    required this.onScaleChanged,
  });

  final VoidCallback onClose;
  final ValueChanged<double> onScaleChanged;

  @override
  Widget build(BuildContext context) {
    final cfg = Config.instance;
    return Material(
      color: const Color(0xFFFDF7FA),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: AnimatedBuilder(
              animation: cfg,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),
                children: [
                  _section('外观', [
                    _slider('尺寸', cfg.petScale, 0.35, 2.5, onScaleChanged),
                    _slider('常态透明度', cfg.normalOpacity, 0.3, 1,
                        cfg.setNormalOpacity),
                    _slider('穿透时透明度', cfg.clickThroughOpacity, 0.1, 1,
                        cfg.setClickThroughOpacity),
                  ]),
                  _section('交互', [
                    _switch('鼠标穿透（背景直接放行）', cfg.clickThrough,
                        cfg.setClickThrough,
                        subtitle: '宠物半透明且不可点，右上角小眼睛按钮始终可点，随时恢复'),
                    _switch('松手重力下落', cfg.gravityFall, cfg.setGravityFall,
                        subtitle: '关闭时拖到哪里就停在哪里'),
                    _switch('键盘互动 Bongo Cat', cfg.bongoHook, cfg.setBongoHook,
                        subtitle: '默认关闭 · 全局键盘钩子，可能触发杀软提示，游戏时建议关闭'),
                  ]),
                  _section('氛围', [
                    _switch('闲置台词气泡', cfg.dialogue, cfg.setDialogue),
                    _switch('音效', cfg.sound, cfg.setSound),
                    _slider('音量', cfg.volume, 0, 1, cfg.setVolume),
                    _switch('随机眨眼', cfg.idleBlink, cfg.setIdleBlink),
                  ]),
                  _section('系统', [
                    _switch('开机自启', cfg.autostart, cfg.setAutostart),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.pets, size: 18, color: Color(0xFFB0567A)),
          const SizedBox(width: 8),
          const Text('MyPet 设置',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFFB0567A))),
          const Spacer(),
          IconButton(
            tooltip: '关闭设置',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
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
                      fontWeight: FontWeight.bold, color: Color(0xFFB0567A))),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
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
          divisions: ((max - min) >= 1 ? ((max - min) * 100).round() : 70),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
      value: value,
      onChanged: onChanged,
    );
  }
}

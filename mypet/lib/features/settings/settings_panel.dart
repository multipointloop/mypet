import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/rig_model.dart';
import '../../core/rig_view.dart';
import '../../core/trace.dart';
import '../pet/pet_engine.dart';

/// Windows 设置面板：直接嵌在宠物窗口内渲染，不再另开引擎/窗口。
///
/// * 面板自己绘制不透明底色（宠物窗口保持透明 + 不做 DWM 重设）；
/// * 所有控件操作同一个 [Config] 实例，无跨引擎轮询；
/// * 右侧是同一个 [PetEngine] 驱动的实时预览：拖尺寸滑杆只改配置与预览，
///   窗口本身不缩放（窗口几何由 WindowsWindowService 在退出面板时统一处理）。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.rig,
    required this.engine,
    required this.onClose,
    required this.onScaleChanged,
    required this.onApplied,
    required this.maxScale,
  });

  final RigData rig;
  final PetEngine engine;
  final VoidCallback onClose;
  final ValueChanged<double> onScaleChanged;

  /// 任何改动落库后回调一次：把设置即时下推平台（音效/音量/Bongo/自启…）。
  /// 穿透与窗口几何由 WindowsWindowService 在面板态闸门内延后处理。
  final VoidCallback onApplied;

  /// 本机可容纳的最大尺寸（由工作区高度换算，避免放大后腿部被切）。
  final double maxScale;

  static const double _kPreviewZoom = 0.30;

  @override
  Widget build(BuildContext context) {
    final cfg = Config.instance;
    return Material(
      color: const Color(0xFFFDF7FA),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: cfg,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.fromLTRB(14, 2, 8, 18),
                      children: [
                        _section('外观', [
                          _slider('尺寸', cfg.petScale, 0.35, maxScale, onScaleChanged),
                          _slider('常态透明度', cfg.normalOpacity, 0.3, 1,
                              cfg.setNormalOpacity),
                          _slider('穿透时透明度', cfg.clickThroughOpacity, 0.1, 1,
                              cfg.setClickThroughOpacity),
                        ]),
                        _section('交互', [
                          _switch('鼠标穿透（背景直接放行）', cfg.clickThrough,
                              cfg.setClickThrough,
                              subtitle: '宠物半透明且不可点；面板关闭后才生效，避免把面板自己锁死'),
                          _switch('松手重力下落', cfg.gravityFall, cfg.setGravityFall,
                              subtitle: '关闭时拖到哪里就停在哪里'),
                          _switch('键盘互动 Bongo Cat', cfg.bongoHook,
                              cfg.setBongoHook,
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
                          _switch('记录诊断日志', cfg.diagnostics,
                              cfg.setDiagnostics,
                              subtitle: '默认开启；关闭后不再写入任何日志（保护隐私）'),
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: const Text('打开日志目录',
                                style: TextStyle(fontSize: 13.5)),
                            subtitle: Text(
                              Trace.logDir?.path ?? '日志目录尚未就绪',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black45),
                            ),
                            trailing: const Icon(Icons.folder_open, size: 18),
                            onTap: () => Trace.openLogDir(),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                SizedBox(width: 236, child: _preview(cfg)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 右侧实时预览：与宠物窗口同一套图层/姿态，仅按 [_kPreviewZoom] 缩小展示。
  /// IgnorePointer 保证它只做展示，不抢事件。
  Widget _preview(Config cfg) {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Text('实时预览', style: TextStyle(fontSize: 11, color: Colors.black45)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: engine,
                builder: (context, _) {
                  final scale = engine.scale * _kPreviewZoom;
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: rig.canvasW * scale,
                        height: rig.canvasH * scale,
                        child: PetRigView(
                          rig: rig,
                          pose: engine.pose(),
                          scale: scale,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: cfg,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '×${cfg.petScale.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB0567A)),
            ),
          ),
        ),
      ],
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
          onChanged: (v) {
            onChanged(v);
            onApplied();
          },
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
      onChanged: (v) {
        onChanged(v);
        onApplied();
      },
    );
  }
}

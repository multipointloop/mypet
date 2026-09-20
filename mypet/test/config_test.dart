import 'package:flutter_test/flutter_test.dart';
import 'package:mypet/core/config.dart';
import 'package:mypet/core/trace.dart';

void main() {
  test('尺寸夹取在 0.35..2.5', () {
    final cfg = Config.instance;
    cfg.setScale(9.9);
    expect(cfg.petScale, 2.5);
    cfg.setScale(0.01);
    expect(cfg.petScale, 0.35);
    cfg.setScale(1.2);
    expect(cfg.petScale, 1.2);
  });

  test('双透明度夹取范围', () {
    final cfg = Config.instance;
    cfg.setNormalOpacity(0.0);
    expect(cfg.normalOpacity, 0.30);
    cfg.setNormalOpacity(5.0);
    expect(cfg.normalOpacity, 1.0);
    cfg.setClickThroughOpacity(0.0);
    expect(cfg.clickThroughOpacity, 0.10);
    cfg.setClickThroughOpacity(0.55);
    expect(cfg.clickThroughOpacity, 0.55);
  });

  test('诊断日志开关即时作用于 Trace', () {
    final cfg = Config.instance;
    cfg.setDiagnostics(false);
    expect(Trace.enabled, isFalse);
    cfg.setDiagnostics(true);
    expect(Trace.enabled, isTrue);
  });

  test('开关类设置可读回', () {
    final cfg = Config.instance;
    cfg.setBongoHook(true);
    expect(cfg.bongoHook, isTrue);
    cfg.setBongoHook(false);
    expect(cfg.bongoHook, isFalse);
    cfg.setGravityFall(true);
    expect(cfg.gravityFall, isTrue);
    cfg.setDialogue(false);
    expect(cfg.dialogue, isFalse);
  });
}

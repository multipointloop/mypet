import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypet/core/audio_service.dart';
import 'package:mypet/core/rig_model.dart';
import 'package:mypet/features/pet/pet_engine.dart';

RigData rig() => RigData.parse(jsonEncode({
      'canvas': {'w': 1000, 'h': 1400},
      'layers': [
        {'name': 'body', 'crop': [0, 600, 1000, 1400], 'z': 0},
      ],
      'regions': {
        'head': [0, 0, 1000, 600],
        'body': [0, 600, 700, 1400],
        'tail': [700, 600, 1000, 1400],
      },
    }));

void main() {
  setUpAll(() => AudioService.instance.enabled = false);

  test('hitRegion 用 scale 反解画布坐标并命中 head/body/tail', () {
    final e = PetEngine()
      ..rig = rig()
      ..scale = 0.5;
    expect(e.hitRegion(const Offset(200, 100)), PetRegion.head);
    expect(e.hitRegion(const Offset(200, 350)), PetRegion.body);
    expect(e.hitRegion(const Offset(400, 350)), PetRegion.tail);
    expect(e.hitRegion(const Offset(20, 1000)), PetRegion.none);
  });

  test('rig 未加载时返回 none', () {
    final e = PetEngine();
    expect(e.hitRegion(const Offset(10, 10)), PetRegion.none);
  });

  test('bongoTap 分别驱动左右爪计时', () {
    final e = PetEngine();
    e.bongoTap(left: true);
    expect(e.bongoLeftT, greaterThan(0));
    expect(e.bongoRightT, 0);
    e.bongoTap(left: false);
    expect(e.bongoRightT, greaterThan(0));
  });

  test('feedPointer 把半径外的向量归一化为单位圆盘', () {
    final e = PetEngine();
    e.feedPointer(const Offset(1000, 500), const Offset(0, 500), 100);
    expect(e.gazeTarget.distance, closeTo(1.0, 1e-9));
    e.feedPointer(const Offset(50, 500), const Offset(0, 500), 100);
    expect(e.gazeTarget.distance, closeTo(0.5, 1e-9));
  });

  test('打瞌睡时 pose 半闭眼', () {
    final e = PetEngine()..mood = PetMood.sleepy;
    expect(e.pose().blink, 0.55);
  });
}

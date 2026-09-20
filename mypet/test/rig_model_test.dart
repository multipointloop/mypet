import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypet/core/rig_model.dart';

void main() {
  group('RigData.parse', () {
    test('解析画布 / 图层 z 序 / 锚点 / 命中区 / 物理参数', () {
      final rig = RigData.parse(jsonEncode({
        'canvas': {'w': 992, 'h': 1400},
        'layers': [
          {'name': 'head', 'crop': [195, 322, 840, 640], 'z': 2},
          {'name': 'tail', 'crop': [585, 995, 885, 1175], 'z': 0},
          {'name': 'body', 'crop': [198, 615, 872, 1400], 'z': 1},
        ],
        'anchors': {'eyeL': [466, 537]},
        'regions': {'head': [195, 322, 840, 615]},
        'params': {
          'pupilMax': [6, 3.5],
          'headShift': [3, 2],
          'headRotDeg': 4,
          'smoothing': 12,
          'gravity': 2000,
          'bounce': 0.35,
        },
      }));
      expect(rig.canvasW, 992);
      expect(rig.canvasH, 1400);
      expect(rig.layers.map((l) => l.name).toList(), ['tail', 'body', 'head']);
      expect(rig.anchor('eyeL'), const Offset(466, 537));
      expect(rig.anchor('missing'), isNull);
      expect(rig.region('head')!.contains(const Offset(300, 400)), isTrue);
      expect(rig.region('head')!.contains(const Offset(300, 900)), isFalse);
      expect(rig.pupilMaxX, 6);
      expect(rig.pupilMaxY, 3.5);
      expect(rig.headRotDeg, 4);
      expect(rig.gravity, 2000);
      expect(rig.bounce, 0.35);
    });

    test('z 缺省时按出现顺序递增，asset 按层名拼接', () {
      final rig = RigData.parse(jsonEncode({
        'layers': [
          {'name': 'body', 'crop': [0, 0, 10, 10]},
          {'name': 'head', 'crop': [0, 0, 10, 10]},
        ],
      }));
      expect(rig.layers.map((l) => l.zOrder).toList(), [0, 1]);
      expect(rig.layers.first.asset, 'assets/parts/body.png');
    });

    test('脏 JSON 不抛异常，回退默认画布与空图层', () {
      final rig = RigData.parse('{ this is not json');
      expect(rig.layers, isEmpty);
      expect(rig.canvasW, 990);
      expect(rig.canvasH, 1386);
    });

    test('真实 assets/rig.json 可解析：5 图层与关键锚点/命中区齐全', () {
      final raw = File('assets/rig.json').readAsStringSync();
      final rig = RigData.parse(raw);
      expect(rig.canvasW, 992);
      expect(rig.canvasH, 1400);
      expect(rig.layers.map((l) => l.name).toList(),
          ['tail', 'head', 'body', 'eyeL', 'eyeR']);
      expect(rig.anchor('headPivot'), isNotNull);
      expect(rig.anchor('tailPivot'), isNotNull);
      expect(rig.anchor('feet'), isNotNull);
      for (final name in ['head', 'body', 'tail']) {
        expect(rig.region(name), isNotNull, reason: name);
      }
    });
  });
}

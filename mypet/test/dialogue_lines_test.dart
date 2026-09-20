import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypet/features/pet/dialogue_lines.dart';

void main() {
  test('自定义台词优先于内置台词', () {
    final rng = Random(7);
    for (var i = 0; i < 20; i++) {
      expect(pickLine('head', rng, {'head': ['自定义喵']}), '自定义喵');
    }
  });

  test('未自定义 / 空列表时回退内置台词', () {
    final rng = Random(7);
    expect(linePools['head']!.contains(pickLine('head', rng, {})), isTrue);
    expect(
        linePools['head']!.contains(pickLine('head', rng, {'head': []})), isTrue);
    expect(pickLine('unknown_key', rng, null).isNotEmpty, isTrue);
  });

  test('每个可编辑键都有内置默认台词与显示名', () {
    for (final key in dialogueKeys) {
      expect(defaultLines(key), isNotEmpty, reason: key);
      expect(dialogueLabels[key], isNotNull, reason: key);
    }
  });
}
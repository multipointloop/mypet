import 'dart:convert';

import 'package:flutter/material.dart';

/// Parsed rig.json - the single source of truth that maps the sliced PNG
/// layers onto a shared canvas coordinate system.
class RigData {
  const RigData({
    required this.canvasW,
    required this.canvasH,
    required this.layers,
    required this.anchors,
    required this.regions,
    required this.pupilMaxX,
    required this.pupilMaxY,
    required this.headShiftX,
    required this.headShiftY,
    required this.headRotDeg,
    required this.smoothing,
    required this.gravity,
    required this.bounce,
  });

  final double canvasW;
  final double canvasH;
  final List<RigLayer> layers; // draw order: index 0 = bottom
  final Map<String, Offset> anchors;
  final Map<String, Rect> regions;
  final double pupilMaxX, pupilMaxY;
  final double headShiftX, headShiftY;
  final double headRotDeg;
  final double smoothing; // exponential lerp factor per second
  final double gravity; // px/s^2 in rig-canvas space
  final double bounce; // restitution after landing

  Offset? anchor(String name) => anchors[name];
  Rect? region(String name) => regions[name];

  static Future<RigData> load({required Future<String> Function(String) readAsset}) async {
    final raw = await readAsset('assets/rig.json');
    return RigData.parse(raw);
  }

  factory RigData.parse(String raw) {
    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // keep an empty rig on parse failure
    }
    final layers = <RigLayer>[];
    for (final l in (json['layers'] as List<dynamic>? ?? [])) {
      final m = l as Map<String, dynamic>;
      final c = m['crop'] as List<dynamic>;
      layers.add(RigLayer(
        name: m['name'] as String,
        crop: Rect.fromLTRB((c[0] as num).toDouble(), (c[1] as num).toDouble(),
            (c[2] as num).toDouble(), (c[3] as num).toDouble()),
        zOrder: (m['z'] as num?)?.toInt() ?? layers.length,
      ));
    }
    layers.sort((a, b) => a.zOrder.compareTo(b.zOrder));

    Offset anchorOf(dynamic v) {
      if (v is List && v.length >= 2) {
        return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
      }
      return Offset.zero;
    }

    Rect regionOf(dynamic v) {
      if (v is List && v.length >= 4) {
        return Rect.fromLTRB((v[0] as num).toDouble(), (v[1] as num).toDouble(),
            (v[2] as num).toDouble(), (v[3] as num).toDouble());
      }
      return Rect.zero;
    }

    final anchorsRaw = json['anchors'] as Map<String, dynamic>? ?? {};
    final regionsRaw = json['regions'] as Map<String, dynamic>? ?? {};
    final params = json['params'] as Map<String, dynamic>? ?? {};

    return RigData(
      canvasW: (json['canvas']?['w'] as num?)?.toDouble() ?? 990,
      canvasH: (json['canvas']?['h'] as num?)?.toDouble() ?? 1386,
      layers: layers,
      anchors: anchorsRaw.map((k, v) => MapEntry(k, anchorOf(v))),
      regions: regionsRaw.map((k, v) => MapEntry(k, regionOf(v))),
      pupilMaxX: _pair(params['pupilMax'], 0, 6),
      pupilMaxY: _pair(params['pupilMax'], 1, 3.5),
      headShiftX: _pair(params['headShift'], 0, 3),
      headShiftY: _pair(params['headShift'], 1, 2),
      headRotDeg: (params['headRotDeg'] as num?)?.toDouble() ?? 4,
      smoothing: (params['smoothing'] as num?)?.toDouble() ?? 12,
      gravity: (params['gravity'] as num?)?.toDouble() ?? 2000,
      bounce: (params['bounce'] as num?)?.toDouble() ?? 0.35,
    );
  }

  static double _pair(dynamic v, int i, double dflt) {
    if (v is List && v.length > i) return (v[i] as num).toDouble();
    return dflt;
  }
}

class RigLayer {
  const RigLayer({
    required this.name,
    required this.crop,
    required this.zOrder,
  });

  final String name;
  final Rect crop;
  final int zOrder;

  String get asset => 'assets/parts/$name.png';
}

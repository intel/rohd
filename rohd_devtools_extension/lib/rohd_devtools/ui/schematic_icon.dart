// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_icon.dart
// Custom icon: three colored blocks connected by orthogonal lines,
// resembling a small schematic / block diagram.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A custom-painted icon showing three colored rectangles connected
/// by orthogonal (right-angle) wires — a miniature schematic diagram.
class SchematicIcon extends StatelessWidget {
  /// Creates a schematic icon at the given [size].
  const SchematicIcon({super.key, this.size = 20, this.brightness});

  /// Icon size in logical pixels (width = height).
  final double size;

  /// Override brightness to force light/dark wire color.
  /// If null, uses the ambient [Theme.of(context).brightness].
  final Brightness? brightness;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('size', size))
      ..add(EnumProperty<Brightness>('brightness', brightness));
  }

  @override

  /// Builds the custom-painted schematic icon.
  Widget build(BuildContext context) {
    final effectiveBrightness = brightness ?? Theme.of(context).brightness;
    return CustomPaint(
      size: Size.square(size),
      painter: _SchematicIconPainter(effectiveBrightness),
    );
  }
}

class _SchematicIconPainter extends CustomPainter {
  _SchematicIconPainter(this.brightness);

  final Brightness brightness;

  @override

  /// Paints the schematic-style icon.
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    final bw = s * 0.30;
    final bh = s * 0.22;
    final r = s * 0.04;

    final ax = s * 0.02;
    final ay = s * 0.08;
    final bx = s * 0.02;
    final by = s * 0.62;
    final cx = s * 0.64;
    final cy = s * 0.38;

    final wireColor =
        brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    final wirePaint = Paint()
      ..color = wireColor
      ..strokeWidth = s * 0.045
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final jx = s * 0.52;
    final aPortY = ay + bh / 2;
    final bPortY = by + bh / 2;
    final cPortY = cy + bh / 2;

    final wireA = Path()
      ..moveTo(ax + bw, aPortY)
      ..lineTo(jx, aPortY)
      ..lineTo(jx, cPortY);
    canvas.drawPath(wireA, wirePaint);

    final wireB = Path()
      ..moveTo(bx + bw, bPortY)
      ..lineTo(jx, bPortY)
      ..lineTo(jx, cPortY);
    canvas.drawPath(wireB, wirePaint);

    final wireC = Path()
      ..moveTo(jx, cPortY)
      ..lineTo(cx, cPortY);
    canvas.drawPath(wireC, wirePaint);

    final dotPaint = Paint()..color = wireColor;
    canvas.drawCircle(Offset(jx, cPortY), s * 0.04, dotPaint);

    const colorA = Color(0xFF4A90D9);
    const colorB = Color(0xFF50B86C);
    const colorC = Color(0xFFE8943A);

    void drawBlock(double x, double y, Color color) {
      final rect = RRect.fromLTRBR(x, y, x + bw, y + bh, Radius.circular(r));
      final fill = Paint()..color = color;
      canvas.drawRRect(rect, fill);
      final border = Paint()
        ..color = color.withAlpha(200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02;
      canvas.drawRRect(rect, border);
    }

    drawBlock(ax, ay, colorA);
    drawBlock(bx, by, colorB);
    drawBlock(cx, cy, colorC);
  }

  @override
  bool shouldRepaint(_SchematicIconPainter old) => old.brightness != brightness;
}

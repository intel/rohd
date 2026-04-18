// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// capture_boundary.dart
// One-call RepaintBoundary → PNG export with toast feedback.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:export_png/export_png.dart' as export_png;

/// Capture a [RepaintBoundary] identified by [boundaryKey], encode to PNG,
/// save/download, and show a toast.
///
/// [filePrefix] is used as the first part of the file name
/// (e.g. `"schematic"` → `schematic_1713052800000.png`).
///
/// Returns `true` if the export succeeded.
Future<bool> captureBoundaryToPng(
  BuildContext context, {
  required GlobalKey boundaryKey,
  String filePrefix = 'export',
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    debugPrint('[ExportPng] No RepaintBoundary found');
    return false;
  }

  final pixelRatio = math.min(
    3.0,
    MediaQuery.of(context).devicePixelRatio,
  );
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  if (byteData == null) {
    debugPrint('[ExportPng] Failed to encode PNG');
    return false;
  }

  final pngBytes = byteData.buffer.asUint8List();
  final fileName = '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.png';

  try {
    final savedPath = await export_png.savePngBytes(pngBytes, fileName);
    final msg =
        savedPath != null ? 'Saved: $savedPath' : 'Downloaded $fileName';
    debugPrint('[ExportPng] $msg');
    if (context.mounted) {
      export_png.showExportToast(context, msg);
    }
    return true;
  } on Object catch (e) {
    debugPrint('[ExportPng] Export failed: $e');
    if (context.mounted) {
      export_png.showExportToast(context, 'Export failed: $e');
    }
    return false;
  }
}

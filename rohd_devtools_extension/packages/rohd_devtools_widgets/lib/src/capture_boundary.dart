// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// capture_boundary.dart
// One-call RepaintBoundary → PNG export with toast feedback.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart' as export_png;

/// Capture a [RepaintBoundary] identified by [boundaryKey], encode to PNG,
/// save/download, and show a toast.
///
/// [filePrefix] is used as the first part of the file name
/// (e.g. `"schematic"` → `schematic_1713052800000.png`).
///
/// When [saveFn] is provided it is used **instead** of the default platform
/// save/download.  This allows callers (e.g. VS Code webview hosts) to route
/// the PNG bytes through a native Save dialog.  [saveFn] receives the raw PNG
/// bytes and a suggested file name, and should return the saved path (or null
/// if no path feedback is available).
///
/// [pixelRatio] controls the output resolution multiplier.  Defaults to 2.0
/// which works well in webview-constrained environments and keeps PNG sizes
/// manageable for postMessage serialisation.  Callers that need print-quality
/// output (e.g. schematic exports) should pass a higher value explicitly.
///
/// Returns `true` if the export succeeded.
Future<bool> captureBoundaryToPng(
  BuildContext context, {
  required GlobalKey boundaryKey,
  String filePrefix = 'export',
  double pixelRatio = 2.0,
  Future<String?> Function(Uint8List pngBytes, String fileName)? saveFn,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    debugPrint('[ExportPng] No RepaintBoundary found');
    return false;
  }

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
    final String? savedPath;
    if (saveFn != null) {
      savedPath = await saveFn(pngBytes, fileName);
    } else {
      savedPath = await export_png.savePngBytes(pngBytes, fileName);
    }
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

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// save_png_native.dart
// Native (Linux/macOS/Windows) implementation: saves PNG bytes to a file.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';
import 'dart:typed_data';

/// Save [pngBytes] to a file named [fileName] in the current directory.
/// Returns the absolute path of the saved file.
Future<String?> savePngBytes(Uint8List pngBytes, String fileName) async {
  final dir = Directory.current.path;
  final filePath = '$dir/$fileName';
  await File(filePath).writeAsBytes(pngBytes);
  return filePath;
}

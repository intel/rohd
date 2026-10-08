// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// save_png_native_test.dart
// Tests for native PNG byte saving.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/src/save_png_native.dart' as native;

void main() {
  test('writes PNG bytes into the current directory', () async {
    final previousDirectory = Directory.current;
    final tempDirectory = await Directory.systemTemp.createTemp(
      'rohd_devtools_widgets_save_png_',
    );
    addTearDown(() async {
      Directory.current = previousDirectory;
      await tempDirectory.delete(recursive: true);
    });

    Directory.current = tempDirectory;
    final savedPath = await native.savePngBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      'capture.png',
    );

    expect(savedPath, '${tempDirectory.path}/capture.png');
    expect(await File(savedPath!).readAsBytes(), [1, 2, 3, 4]);
  });
}

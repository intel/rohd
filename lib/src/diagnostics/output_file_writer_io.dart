// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// output_file_writer_io.dart
// Native output file writer.
//
// 2026 July 5
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

/// Writes [contents] to [path], creating parent directories as needed.
void writeOutputTextFile(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

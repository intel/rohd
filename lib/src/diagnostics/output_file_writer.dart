// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// output_file_writer.dart
// Platform-neutral output file writer stub.
//
// 2026 July 5
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Writes [contents] to [path] on platforms that support file IO.
void writeOutputTextFile(String path, String contents) {
  throw UnsupportedError('File output is not supported on this platform.');
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// save_png_stub.dart
// Stub for conditional import — never actually imported at runtime.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:typed_data';

/// Stub — always throws.
Future<String?> savePngBytes(Uint8List pngBytes, String fileName) =>
    throw UnsupportedError('savePngBytes not supported on this platform');

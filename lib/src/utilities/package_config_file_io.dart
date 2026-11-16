// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// package_config_file_io.dart
// Native source-trace package configuration reader.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

/// Reads the package configuration from [packageRoot], if it exists.
String? readPackageConfig(String packageRoot) {
  final file = File('$packageRoot/.dart_tool/package_config.json');
  return file.existsSync() ? file.readAsStringSync() : null;
}

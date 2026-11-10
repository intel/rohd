// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// package_test.dart
// Validate the DevTools extension's package identity and metadata.
//
// 2026 November 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('DevTools extension matches its package name and version', () {
    final package =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final extension = loadYaml(
      File('extension/devtools/config.yaml').readAsStringSync(),
    ) as YamlMap;

    expect(package['name'], 'rohd_live_debugger');
    expect(extension['name'], package['name']);
    expect(extension['version'], package['version']);
    expect(extension['requiresConnection'], isFalse);
  });
}

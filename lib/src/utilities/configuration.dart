/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// configuration.dart
/// Extract configuration of ROHD from pubspec YAML
///
/// 2021 May 7
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'dart:io';
import 'package:yaml/yaml.dart';

/// A utility to extract the ROHD configuration from pubspec.yaml
/// configuration document.
abstract class Configuration {
  /// A getter to return the current configuration of ROHD
  static String get getConfig {
    const config = './pubspec.yaml';
    final f = File(config);
    final yamlText = f.readAsStringSync();
    final yaml = loadYaml(yamlText) as Map;

    return yaml['version'] as String;
  }
}

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
  static Map<String, dynamic> get getConfig {
    const config = './pubspec.yaml';
    final f = File(config);
    final yamlText = f.readAsStringSync();
    final yaml = loadYaml(yamlText) as Map;

    return {
      'name': yaml['name'] as String,
      'description': yaml['description'] as String,
      'version': yaml['version'] as String,
      'homepage': yaml['homepage'] as String,
      'repository': yaml['repository'] as String,
      'issue_tracker': yaml['issue_tracker'] as String,
      'documentation': yaml['documentation'] as String,
      'environment': yaml['environment'] as Object,
      'dependencies': yaml['dependencies'] as Object,
      'dev_dependencies': yaml['dev_dependencies'] as Object
    };
  }
}

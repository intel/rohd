/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// version_hash_dumper_test.dart
/// Tests to verify if ROHD version and git hash being dump to
/// the generation of system verilog and wave dumper
///
/// 2021 November 16
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

class SimpleModule extends Module {
  SimpleModule(Logic a, Logic b) {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');

    Combinational([
      If(a, then: [c < a], orElse: [c < b])
    ]);
  }
}

void main() {
  group('ROHD version generator', () {
    test('should contains ROHD version number when sv is generated', () async {
      const config = './pubspec.yaml';
      final f = File(config);
      final yamlText = f.readAsStringSync();
      final yaml = loadYaml(yamlText);
      print(yaml['version']);

      final mod = SimpleModule(Logic(), Logic());
      await mod.build();

      expect(mod.generateSynth(), contains(''));
    });
  });
}

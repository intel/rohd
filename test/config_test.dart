/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// version_hash_dumper_test.dart
/// Tests to verify if ROHD configuration being output to
/// the generation of system verilog.
///
/// 2022 December 1
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'dart:io';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'wave_dumper_test.dart';

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

void main() async {
  test(
      'should return true if rohd version is similar'
      ' in both pubspec.yaml and config class.', () async {
    final yamlText = File('./pubspec.yaml').readAsStringSync();
    final yaml = loadYaml(yamlText) as Map;

    expect(Config.version, equals(yaml['version']));
  });

  test('should contains ROHD version number when sv is generated.', () async {
    const version = Config.version;

    final mod = SimpleModule(Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains(version));
  });

  test('should contains ROHD version number when wavedumper is generated.',
      () async {
    const version = Config.version;

    final mod = SimpleModule(Logic(), Logic());
    await mod.build();

    const dumpName = 'simplemodule';

    createTemporaryDump(mod, dumpName);

    await Simulator.run();

    final vcdContents = await File(temporaryDumpPath(dumpName)).readAsString();
    expect(vcdContents, contains(version));

    deleteTemporaryDump(dumpName);
  });
}

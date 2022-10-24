/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// definition_name_test.dart
/// Tests for definition names (including reserving them) of Modules.
///
/// 2022 March 7
/// Author: Max Korbel <max.korbel@intel.com>

// ignore_for_file: avoid_positional_boolean_parameters

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'dart:io';

class ValidDefNameModule extends Module {
  ValidDefNameModule(Logic a, String defName)
      : super(
          name: 'specialNameInstance',
          reserveName: false,
          definitionName: defName,
          reserveDefinitionName: true,
        ) {
    addInput('a', a, width: a.width);
  }
}

class TopModule extends Module {
  TopModule(Logic a, bool causeDefConflict, bool causeInstConflict)
      : super(name: 'topModule') {
    a = addInput('a', a);

    // note: order matters
    SpeciallyNamedModule([a, a].swizzle(), causeDefConflict, causeInstConflict);
    SpeciallyNamedModule(a, true, causeInstConflict);
  }
}

class SpeciallyNamedModule extends Module {
  SpeciallyNamedModule(Logic a, bool reserveDefName, bool reserveInstanceName)
      : super(
          name: 'specialNameInstance',
          reserveName: reserveInstanceName,
          definitionName: 'specialName',
          reserveDefinitionName: reserveDefName,
        ) {
    addInput('a', a, width: a.width);
  }
}

void main() {
  group('definition name', () {
    test('should return sanitized definition name if given invalid syntax',
        () async {
      final mod = ValidDefNameModule(Logic(), '/--**definitionName+');
      await mod.build();

      final res = mod.generateSynth();
      final out = File('output.txt').openWrite();
      out.write(res);

      expect(res, contains('_____definitionName_'));
    });

    test('respected with no conflicts', () async {
      final mod = SpeciallyNamedModule(Logic(), false, false);
      await mod.build();
      expect(mod.generateSynth(), contains('module specialName('));
    });
    test('uniquified with conflicts', () async {
      final mod = TopModule(Logic(), false, false);
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('module specialName('));
      expect(sv, contains('module specialName_0('));
    });
    test('reserved throws exception with conflicts', () async {
      final mod = TopModule(Logic(), true, false);
      await mod.build();
      expect(mod.generateSynth, throwsException);
    });
  });

  group('instance name', () {
    test('uniquified with conflicts', () async {
      final mod = TopModule(Logic(), false, false);
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('specialNameInstance('));
      expect(sv, contains('specialNameInstance_0('));
    });
    test('reserved throws exception with conflicts', () async {
      final mod = TopModule(Logic(), false, true);
      expect(() async {
        await mod.build();
      }, throwsException);
    });
  });
}

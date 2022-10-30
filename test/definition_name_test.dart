/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// definition_name_test.dart
/// Unit tests for name definition usage
///
/// 2022 October 26
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/name_exceptions.dart';
import 'package:test/test.dart';

class DefinitionName {
  String? name;
  bool isReserved;

  DefinitionName({required this.name, required this.isReserved});

  static String getValidName() => 'specialName';
  static String getInvalidName() => '/--**definitionName+';
}

class ValidDefNameModule extends Module {
  ValidDefNameModule(Logic a, DefinitionName defName)
      : super(
          name: 'specialNameInstance',
          reserveName: false,
          definitionName: defName.name,
          reserveDefinitionName: defName.isReserved,
        ) {
    addInput('a', a, width: a.width);
  }
}

// ignore: camel_case_types
class byte extends Module {
  byte(Logic a) {
    addInput('a', a, width: a.width);
  }
}

void main() {
  group('GIVEN that Reserved Definition Name is TRUE,', () {
    test('WHEN definition name is valid, THEN expect to compile successfully.',
        () async {
      final defName =
          DefinitionName(name: DefinitionName.getValidName(), isReserved: true);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      final sv = mod.generateSynth();
      // Then it should return compile successfully
      expect(sv, contains('module specialName('));
    });
    test('WHEN definition name is invalid, THEN expect to throw exception.',
        () async {
      final defName = DefinitionName(
          name: DefinitionName.getInvalidName(), isReserved: true);
      expect(() async {
        ValidDefNameModule(Logic(), defName);
      }, throwsA((dynamic e) => e is InvalidReservedNameException));
    });
    test('WHEN definition name is null, THEN expect to throw exception.',
        () async {
      final defName = DefinitionName(name: null, isReserved: true);
      expect(() async {
        ValidDefNameModule(Logic(), defName);
      }, throwsA((dynamic e) => e is NullReservedNameException));
    });
  });

  group('GIVEN that Reserved Definition Name is FALSE,', () {
    test(
        'WHEN definition name is valid, THEN expected to compile successfully.',
        () async {
      final defName = DefinitionName(
          name: DefinitionName.getValidName(), isReserved: false);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      final sv = mod.generateSynth();
      // Then it should return compile successfully
      expect(sv, contains('module specialName('));
    });
    test('WHEN definition name is invalid, THEN expected to sanitize name.',
        () async {
      final defName = DefinitionName(
          name: DefinitionName.getInvalidName(), isReserved: false);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('_____definitionName_'));
    });
    group('WHEN definition name is null,', () {
      test('THEN expected to auto initialize name.', () async {
        final defName = DefinitionName(name: null, isReserved: false);
        final mod = ValidDefNameModule(Logic(), defName);
        await mod.build();
        final sv = mod.generateSynth();
        expect(sv, contains('module ValidDefNameModule('));
      });
      test(
          'AND runtime type name is invalid, '
          'THEN expect to sanitize the result', () async {
        final mod = byte(Logic());
        await mod.build();
        final sv = mod.generateSynth();
        expect(sv, contains('module byte_'));
      });
    });
  });
}

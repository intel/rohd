// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_services_test.dart
// Unit tests for ModuleServices and SvService.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SimpleModule extends Module {
  SimpleModule(Logic a) : super(name: 'simple') {
    a = addInput('a', a);
    addOutput('b') <= ~a;
  }
}

void main() {
  tearDown(ModuleServices.instance.reset);

  group('ModuleServices', () {
    test('rootModule is set after build', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      expect(ModuleServices.instance.rootModule, equals(mod));
    });

    test('hierarchyJSON returns valid JSON', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final json = ModuleServices.instance.hierarchyJSON;
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('inspectorJSON matches hierarchyJSON', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      expect(ModuleServices.instance.inspectorJSON,
          equals(ModuleServices.instance.hierarchyJSON));
    });

    test('svJSON returns unavailable when no service registered', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final result =
          jsonDecode(ModuleServices.instance.svJSON) as Map<String, dynamic>;
      expect(result['status'], equals('unavailable'));
    });

    test('reset clears all services', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      expect(ModuleServices.instance.rootModule, isNotNull);
      ModuleServices.instance.reset();
      expect(ModuleServices.instance.rootModule, isNull);
      expect(ModuleServices.instance.svService, isNull);
    });
  });

  group('SvService', () {
    test('registers with ModuleServices on creation', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SvService(mod);
      expect(ModuleServices.instance.svService, equals(sv));
    });

    test('allContents is non-empty', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SvService(mod);
      expect(sv.allContents, isNotEmpty);
    });

    test('contentsByName has entries', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SvService(mod);
      expect(sv.contentsByName, isNotEmpty);
    });

    test('contentsByDefinitionName has entries', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SvService(mod);
      expect(sv.contentsByDefinitionName, isNotEmpty);
      expect(sv.contentsByDefinitionName.containsKey('SimpleModule'), isTrue);
    });

    test('svJSON returns valid JSON after registration', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      SvService(mod);
      final result =
          jsonDecode(ModuleServices.instance.svJSON) as Map<String, dynamic>;
      expect(result['modules'], isList);
    });

    test('writeFiles creates SV files', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SvService(mod);
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        sv.writeFiles(dir.path);
        final files = dir.listSync().whereType<File>().toList();
        expect(files, isNotEmpty);
        expect(files.any((f) => f.path.endsWith('.sv')), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    }, testOn: 'vm');

    test('register false does not register', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      ModuleServices.instance.reset();
      SvService(mod, register: false);
      expect(ModuleServices.instance.svService, isNull);
    });

    test('throws if module not built', () {
      final mod = SimpleModule(Logic());
      expect(() => SvService(mod), throwsException);
    });
  });
}

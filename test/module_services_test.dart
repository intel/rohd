// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_services_test.dart
// Unit tests for ModuleServices, the service base types, and
// SystemVerilogService.
//
// 2026 April 25 Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

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

/// A minimal [ModuleService] used to exercise the type-keyed registry.
class FakeService implements ModuleService {
  FakeService(this.module);

  @override
  final Module module;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'fake'};
}

void main() {
  tearDown(ModuleServices.instance.reset);

  group('ModuleServices registry', () {
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

    test('register and lookup round-trips a service', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final fake = FakeService(mod);
      ModuleServices.instance.register<FakeService>(fake);
      expect(ModuleServices.instance.lookup<FakeService>(), same(fake));
    });

    test('lookup returns null when no service registered', () {
      expect(ModuleServices.instance.lookup<FakeService>(), isNull);
    });

    test('unregister removes a service', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      ModuleServices.instance.register<FakeService>(FakeService(mod));
      ModuleServices.instance.unregister<FakeService>();
      expect(ModuleServices.instance.lookup<FakeService>(), isNull);
    });

    test('reset clears rootModule and all services', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      ModuleServices.instance.register<FakeService>(FakeService(mod));
      expect(ModuleServices.instance.rootModule, isNotNull);

      ModuleServices.instance.reset();
      expect(ModuleServices.instance.rootModule, isNull);
      expect(ModuleServices.instance.lookup<FakeService>(), isNull);
    });
  });

  group('SystemVerilogService', () {
    test('is a CodeGenService', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      expect(SystemVerilogService(mod), isA<CodeGenService>());
    });

    test('allContents is non-empty', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);
      expect(sv.allContents, isNotEmpty);
    });

    test('output is non-empty', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);
      expect(sv.output, isNotEmpty);
    });

    test('instanceTypeOutput returns the instance type contents', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);

      final contents = sv.fileContents.single;
      expect(sv.instanceTypeOutput(contents.name), equals(contents.contents));
      expect(sv.instanceTypeOutput('DoesNotExist'), isNull);
    });

    test('toJson lists generated modules', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);
      expect(sv.toJson()['modules'], isList);
    });

    test('writeFiles creates SV files', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        sv.writeFiles(dir.path);
        final files = dir.listSync().whereType<File>().toList();
        expect(files, isNotEmpty);
        expect(files.any((f) => f.path.endsWith('.sv')), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('write() emits a single file', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        final path = '${dir.path}/out.sv';
        sv.write(path);
        expect(File(path).readAsStringSync(), equals(sv.output));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('write() with multiFile emits a directory of files', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        // Construction with outputPath writes immediately.
        SystemVerilogService(mod, outputPath: dir.path, multiFile: true);
        final files = dir.listSync().whereType<File>().toList();
        expect(files.any((f) => f.path.endsWith('.sv')), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('throws if module not built', () {
      final mod = SimpleModule(Logic());
      expect(() => SystemVerilogService(mod), throwsException);
    });
  });
}

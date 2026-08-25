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
  tearDown(() {
    SystemVerilogService.current = null;
    ModuleServices.instance.reset();
  });

  group('ModuleServices registry', () {
    test('rootModule is set after build', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      expect(ModuleServices.instance.rootModule, equals(mod));
    });

    test('hierarchyJson returns valid JSON', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final json = ModuleServices.instance.hierarchyJson;
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
    test('registers by default', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);

      expect(SystemVerilogService.current, same(sv));
      expect(
        ModuleServices.instance.lookup<SystemVerilogService>(),
        same(sv),
      );
    });

    test('can opt out of registration', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod, register: false);

      expect(SystemVerilogService.current, isNull);
      expect(
        ModuleServices.instance.lookup<SystemVerilogService>(),
        isNull,
      );
      expect(sv.output, isNotEmpty);
    });

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

    test('artifact defaults to the module definition name', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final sv = SystemVerilogService(mod);

      final artifact = sv.artifacts.single;

      expect(artifact.fileName, equals('${mod.definitionName}.sv'));
      expect(artifact.mediaType, equals('text/x-systemverilog'));
      expect(
        (await artifact.openRead().expand((bytes) => bytes).toList())
            .isNotEmpty,
        isTrue,
      );
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

    test('writeOutputs creates SV files', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        SystemVerilogService(
          mod,
          outputDirectory: dir.path,
          multiFile: true,
        ).writeOutputs();
        final files = dir.listSync().whereType<File>().toList();
        expect(files, isNotEmpty);
        expect(files.any((f) => f.path.endsWith('.sv')), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('writeOutputs emits a single file', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        final configuredSv = SystemVerilogService(
          mod,
          outputDirectory: dir.path,
          outputBaseName: 'out',
        )..writeOutputs();
        final path = '${dir.path}/out.sv';
        expect(File(path).readAsStringSync(), equals(configuredSv.output));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('multiFile writeOutputs emits a directory of files', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        SystemVerilogService(
          mod,
          outputDirectory: dir.path,
          multiFile: true,
        ).writeOutputs();
        final files = dir.listSync().whereType<File>().toList();
        expect(files.any((f) => f.path.endsWith('.sv')), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('defaults headers by output layout', () async {
      final mod = SimpleModule(Logic());
      await mod.build();

      final singleFile = SystemVerilogService(mod);
      final multiFile = SystemVerilogService(mod, multiFile: true);

      expect(singleFile.includeHeader, isTrue);
      expect(singleFile.output, startsWith(singleFile.header));
      expect(multiFile.includeHeader, isFalse);
      expect(multiFile.header, isEmpty);
    });

    test('writes headers in either output layout when requested', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('sv_test_');
      try {
        final singlePath = '${dir.path}/single.sv';
        final singleFile = SystemVerilogService(
          mod,
          outputDirectory: dir.path,
          outputBaseName: 'single',
          includeHeader: false,
        )..writeOutputs();
        expect(
          File(singlePath).readAsStringSync(),
          equals(singleFile.allContents),
        );

        final multiFile = SystemVerilogService(
          mod,
          outputDirectory: dir.path,
          multiFile: true,
          includeHeader: true,
        )..writeOutputs();
        final output =
            File('${dir.path}/${multiFile.fileContents.single.name}.sv')
                .readAsStringSync();
        expect(output, startsWith(multiFile.header));
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

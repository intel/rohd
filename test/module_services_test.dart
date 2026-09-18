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
import 'package:rohd/src/diagnostics/inspector_service.dart';
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
  tearDown(() async {
    await Simulator.reset();
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

    test('legacy hierarchyJSON returns the current hierarchy JSON', () async {
      final mod = SimpleModule(Logic());
      await mod.build();

      expect(
        // This verifies that the deprecated compatibility alias still works.
        // ignore: deprecated_member_use_from_same_package
        ModuleTree.instance.hierarchyJSON,
        equals(ModuleTree.instance.hierarchyJson),
      );
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

    test('service current accessors follow latest registrations', () async {
      final mod = SimpleModule(Logic());
      await mod.build();

      final firstWaveform = WaveformService(mod);
      final secondWaveform = WaveformService(mod);
      final firstNetlist = NetlistService(mod);
      final secondNetlist = NetlistService(mod);
      final firstSv = SystemVerilogService(mod);
      final secondSv = SystemVerilogService(mod);

      expect(WaveformService.current, same(secondWaveform));
      expect(NetlistService.current, same(secondNetlist));
      expect(SystemVerilogService.current, same(secondSv));
      expect(ModuleServices.instance.lookup<WaveformService>(),
          isNot(same(firstWaveform)));
      expect(ModuleServices.instance.lookup<NetlistService>(),
          isNot(same(firstNetlist)));
      expect(ModuleServices.instance.lookup<SystemVerilogService>(),
          isNot(same(firstSv)));
    });

    test('service opt-out does not replace a registered service', () async {
      final mod = SimpleModule(Logic());
      await mod.build();

      final waveform = WaveformService(mod);
      final netlist = NetlistService(mod);
      final sv = SystemVerilogService(mod);
      WaveformService(mod, register: false);
      NetlistService(mod, register: false);
      SystemVerilogService(mod, register: false);

      expect(WaveformService.current, same(waveform));
      expect(NetlistService.current, same(netlist));
      expect(SystemVerilogService.current, same(sv));
    });

    test('unregister clears matching service current accessors', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      WaveformService(mod);
      NetlistService(mod);
      SystemVerilogService(mod);

      ModuleServices.instance.unregister<WaveformService>();
      ModuleServices.instance.unregister<NetlistService>();
      ModuleServices.instance.unregister<SystemVerilogService>();

      expect(WaveformService.current, isNull);
      expect(NetlistService.current, isNull);
      expect(SystemVerilogService.current, isNull);
    });

    test('reset clears every service current accessor', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      WaveformService(mod);
      NetlistService(mod);
      SystemVerilogService(mod);

      ModuleServices.instance.reset();

      expect(WaveformService.current, isNull);
      expect(NetlistService.current, isNull);
      expect(SystemVerilogService.current, isNull);
    });
  });

  group('SystemVerilogService', () {
    test('legacy generateSynth does not register a service', () async {
      final mod = SimpleModule(Logic());
      await mod.build();

      // ignore: deprecated_member_use_from_same_package - compatibility coverage
      expect(mod.generateSynth(), isNotEmpty);
      expect(SystemVerilogService.current, isNull);
      expect(
        ModuleServices.instance.lookup<SystemVerilogService>(),
        isNull,
      );
    });

    test('legacy generateSynth preserves ModuleNotBuiltException', () {
      final mod = SimpleModule(Logic());

      // ignore: deprecated_member_use_from_same_package - compatibility coverage
      expect(mod.generateSynth, throwsA(isA<ModuleNotBuiltException>()));
    });

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
      expect(
        () => SystemVerilogService(mod),
        throwsA(isA<ModuleNotBuiltException>()),
      );
    });
  });

  group('NetlistService', () {
    test('throws if module not built', () {
      final mod = SimpleModule(Logic());

      expect(
        () => NetlistService(mod),
        throwsA(isA<ModuleNotBuiltException>()),
      );
    });

    test('uses the synthesized format version across all JSON views', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final netlist = NetlistService(mod);

      final full = jsonDecode(netlist.json) as Map<String, dynamic>;
      final module = jsonDecode(netlist.moduleJson(mod.definitionName))
          as Map<String, dynamic>;
      final slim = jsonDecode(netlist.slimJson) as Map<String, dynamic>;

      expect(netlist.version, equals(full['version']));
      expect(module['version'], equals(full['version']));
      expect(
        (slim['netlist'] as Map<String, dynamic>)['version'],
        equals(full['version']),
      );
    });

    test('construction does not write configured output', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('netlist_test_');
      try {
        final netlist = NetlistService(
          mod,
          outputDirectory: dir.path,
          outputBaseName: 'configured',
        );

        expect(netlist.json, isNotEmpty);
        expect(File('${dir.path}/configured.rohd.json').existsSync(), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('artifact defaults to the module definition name', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final netlist = NetlistService(mod);

      final artifact = netlist.artifacts.single;

      expect(artifact.fileName, equals('${mod.definitionName}.rohd.json'));
      expect(artifact.mediaType, equals('application/json'));
      expect(
        utf8.decode(
          await artifact.openRead().expand((bytes) => bytes).toList(),
        ),
        equals(netlist.json),
      );
    });

    test('writeOutputs writes the configured artifact name', () async {
      final mod = SimpleModule(Logic());
      await mod.build();
      final dir = Directory.systemTemp.createTempSync('netlist_test_');
      try {
        final netlist = NetlistService(
          mod,
          outputDirectory: dir.path,
          outputBaseName: 'out',
        )..writeOutputs();

        final outputFile = File('${dir.path}/out.rohd.json');
        expect(outputFile.existsSync(), isTrue);
        expect(outputFile.readAsStringSync(), equals(netlist.json));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

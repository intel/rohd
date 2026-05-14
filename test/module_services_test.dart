// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_services_test.dart
// Tests for ModuleServices, SvService, and NetlistService.

@TestOn('vm')
library;

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Simple test modules
// ---------------------------------------------------------------------------

class _InverterModule extends Module {
  Logic get out => output('out');

  _InverterModule(Logic inp) : super(name: 'inverter') {
    inp = addInput('inp', inp);
    final out = addOutput('out');
    out <= ~inp;
  }
}

class _TopModule extends Module {
  Logic get out => output('out');

  _TopModule(Logic a, Logic b) : super(name: 'top') {
    a = addInput('a', a);
    b = addInput('b', b);
    final out = addOutput('out');

    final inv = _InverterModule(a);
    out <= inv.out & b;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  group('ModuleServices', () {
    test('rootModule is set by Module.build', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      expect(ModuleServices.instance.rootModule, equals(mod));
    });

    test('hierarchyJSON returns valid JSON after build', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final json = ModuleServices.instance.hierarchyJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['name'], equals('top'));
    });

    test('svJSON returns unavailable when no SvService registered', () {
      final json = ModuleServices.instance.svJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['status'], equals('unavailable'));
    });

    test(
      'netlistJSON returns unavailable when no NetlistService registered',
      () {
        final json = ModuleServices.instance.netlistJSON;
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['status'], equals('unavailable'));
      },
    );

    test('reset clears all services', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      expect(ModuleServices.instance.rootModule, isNotNull);
      ModuleServices.instance.reset();
      expect(ModuleServices.instance.rootModule, isNull);
    });

    test('inspectorJSON returns slim netlist when service registered',
        () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();
      await NetlistService.create(mod);

      final json = ModuleServices.instance.inspectorJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['netlist'], isA<Map<String, dynamic>>());
      final netlist = decoded['netlist'] as Map<String, dynamic>;
      expect(netlist['modules'], isA<Map<String, dynamic>>());
    });

    test('inspectorJSON falls back to hierarchy when no netlist', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final json = ModuleServices.instance.inspectorJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      // Falls back to hierarchy JSON format.
      expect(decoded['name'], equals('top'));
    });

    test('inspectorModuleJSON returns per-module netlist', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();
      final netSvc = await NetlistService.create(mod);

      for (final name in netSvc.moduleNames) {
        final json = ModuleServices.instance.inspectorModuleJSON(name);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['modules'], isA<Map<String, dynamic>>());
      }
    });
  });

  group('SvService', () {
    test('generates SV for a module hierarchy', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final sv = SvService(mod);

      expect(sv.fileContents, isNotEmpty);
      expect(sv.allContents, contains('module'));
      expect(sv.allContents, contains('endmodule'));
    });

    test('registers with ModuleServices by default', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      SvService(mod);

      expect(ModuleServices.instance.svService, isNotNull);
      final json = ModuleServices.instance.svJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['modules'], isA<List<dynamic>>());
    });

    test('register: false does not register', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      SvService(mod, register: false);

      expect(ModuleServices.instance.svService, isNull);
    });

    test('contentsByName returns per-module SV', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final sv = SvService(mod, register: false);
      final byName = sv.contentsByName;

      // Should have at least the top module and the inverter.
      expect(byName.length, greaterThanOrEqualTo(2));
      for (final content in byName.values) {
        expect(content, contains('module'));
      }
    });

    test('synthOutput includes header', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final sv = SvService(mod, register: false);
      expect(sv.synthOutput, contains('Generated by ROHD'));
      expect(sv.synthOutput, contains(sv.allContents));
    });
  });

  group('NetlistService', () {
    test('generates netlist JSON for a module hierarchy', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final netlist = await NetlistService.create(mod);
      final json = netlist.toJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['modules'], isA<Map<String, dynamic>>());
      expect(netlist.moduleNames, isNotEmpty);
    });

    test('registers with ModuleServices by default', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      await NetlistService.create(mod);

      expect(ModuleServices.instance.netlistService, isNotNull);
      final json = ModuleServices.instance.netlistJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['modules'], isA<Map<String, dynamic>>());
    });

    test('register: false does not register', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      await NetlistService.create(mod, register: false);

      expect(ModuleServices.instance.netlistService, isNull);
    });

    test('moduleJson returns single module data', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final netlist = await NetlistService.create(mod, register: false);

      // Query for a module that exists.
      for (final name in netlist.moduleNames) {
        final moduleJson = netlist.moduleJson(name);
        final decoded = jsonDecode(moduleJson) as Map<String, dynamic>;
        expect(decoded['modules'], isA<Map<String, dynamic>>());
        expect((decoded['modules'] as Map).containsKey(name), isTrue);
      }

      // Query for a module that doesn't exist.
      final missing = netlist.moduleJson('nonexistent');
      final decoded = jsonDecode(missing) as Map<String, dynamic>;
      expect(decoded['status'], equals('not_found'));
    });

    test('slimJson returns netlist envelope without connections', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final netlist = await NetlistService.create(mod, register: false);
      final slim = netlist.slimJson;
      final decoded = jsonDecode(slim) as Map<String, dynamic>;

      expect(decoded['netlist'], isA<Map<String, dynamic>>());
      final netlistSection = decoded['netlist'] as Map<String, dynamic>;
      expect(netlistSection['rootInstanceName'], isNotNull);
      expect(netlistSection['modules'], isA<Map<String, dynamic>>());

      // Verify cells have no connections
      final modules = netlistSection['modules'] as Map<String, dynamic>;
      for (final modEntry in modules.values) {
        final cells =
            (modEntry as Map<String, dynamic>)['cells'] as Map<String, dynamic>;
        for (final cellEntry in cells.values) {
          final cell = cellEntry as Map<String, dynamic>;
          expect(cell.containsKey('connections'), isFalse,
              reason: 'Slim cells should not have connections');
        }
      }
    });

    test('synthesizedModules provides read-only access', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build();

      final netlist = await NetlistService.create(mod, register: false);
      final modules = netlist.synthesizedModules;
      expect(modules, isNotEmpty);
      expect(modules.keys, equals(netlist.moduleNames));
    });
  });

  group('Module.build netlistOptions integration', () {
    test('netlistOptions creates and registers NetlistService', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = _TopModule(a, b);
      await mod.build(netlistOptions: const NetlistOptions());

      expect(ModuleServices.instance.netlistService, isNotNull);
      final json = ModuleServices.instance.netlistJSON;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['modules'], isA<Map<String, dynamic>>());
    });
  });
}

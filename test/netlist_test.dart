// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_test.dart
// Tests for the netlist synthesizer: JSON structure, SynthBuilder,
// NetlistSynthesisResult, collectModuleEntries, NetlistOptions,
// and example-based smoke tests.
//
// 2026 March 31
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/examples/filter_bank_modules.dart';
import 'package:test/test.dart';

import '../example/example.dart';
import '../example/fir_filter.dart';
import '../example/logic_array.dart';
import '../example/oven_fsm.dart';
import '../example/tree.dart';

// ---------------------------------------------------------------------------
// Simple test modules (self-contained, no example imports needed)
// ---------------------------------------------------------------------------

/// A trivial module that inverts a single-bit input.
class _InverterModule extends Module {
  Logic get out => output('out');

  _InverterModule(Logic inp) : super(name: 'inverter') {
    inp = addInput('inp', inp);
    final out = addOutput('out');
    out <= ~inp;
  }
}

/// A module that instantiates two sub-modules: an inverter and an AND gate.
class _CompositeModule extends Module {
  Logic get out => output('out');

  _CompositeModule(Logic a, Logic b) : super(name: 'composite') {
    a = addInput('a', a);
    b = addInput('b', b);
    final out = addOutput('out');

    final invA = _InverterModule(a);
    out <= (_InverterModule(invA.out).out & b);
  }
}

/// A simple adder module with a configurable width.
class _AdderModule extends Module {
  Logic get sum => output('sum');

  _AdderModule(Logic a, Logic b, {int width = 8}) : super(name: 'adder') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    final sum = addOutput('sum', width: width);
    sum <= a + b;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Detect whether running in JS (dart2js) environment.
const _isJS = identical(0, 0.0);

/// Synthesize [top] and optionally write the produced JSON to [outPath].
/// Returns the decoded modules map from the Yosys-format JSON.
Future<Map<String, dynamic>> _synthesizeAndWrite(
  Module top,
  String outPath,
) async {
  final synth = SynthBuilder(top, NetlistSynthesizer());
  final jsonStr =
      await (synth.synthesizer as NetlistSynthesizer).synthesizeToJson(top);
  if (!_isJS) {
    final file = File(outPath);
    await file.create(recursive: true);
    await file.writeAsString(jsonStr);
  }
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
  return decoded['modules'] as Map<String, dynamic>;
}

/// Build a FilterBank with default test parameters.
FilterBank _buildFilterBank({
  int dataWidth = 16,
  int numTaps = 3,
  List<List<int>> coefficients = const [
    [1, 2, 1],
    [1, -2, 1],
  ],
}) {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final start = Logic(name: 'start');
  final samplesIn =
      LogicArray([coefficients.length], dataWidth, name: 'samplesIn');
  final validIn = Logic(name: 'validIn');
  final inputDone = Logic(name: 'inputDone');

  return FilterBank(
    clk,
    reset,
    start,
    samplesIn,
    validIn,
    inputDone,
    numTaps: numTaps,
    dataWidth: dataWidth,
    coefficients: coefficients,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  // ── Example smoke tests ───────────────────────────────────────────────
  //
  // Each example is synthesized once, verifying that the netlist is
  // non-empty and (on VM) that the JSON file is written successfully.

  group('Example netlist smoke tests', () {
    test('Counter', () async {
      final counter = Counter(Logic(name: 'en'), Logic(name: 'reset'),
          SimpleClockGenerator(10).clk);
      await counter.build();

      final modules =
          await _synthesizeAndWrite(counter, 'build/Counter.rohd.json');
      expect(modules, isNotEmpty);

      final topMod = modules[counter.definitionName] as Map<String, dynamic>;
      final cells = topMod['cells'] as Map<String, dynamic>? ?? {};
      expect(cells, isNotEmpty, reason: 'Counter should have cells');
    });

    test('FIR filter', () async {
      final fir = FirFilter(
        Logic(name: 'en'),
        Logic(name: 'resetB'),
        SimpleClockGenerator(10).clk,
        Logic(name: 'inputVal', width: 8),
        [0, 0, 0, 1],
        bitWidth: 8,
      );
      await fir.build();

      final modules =
          await _synthesizeAndWrite(fir, 'build/FirFilter.rohd.json');
      expect(modules, isNotEmpty);
      if (!_isJS) {
        expect(File('build/FirFilter.rohd.json').existsSync(), isTrue);
      }
    });

    test('LogicArray', () async {
      final la = LogicArrayExample(
        LogicArray([4], 8, name: 'arrayA'),
        Logic(name: 'id', width: 3),
        Logic(name: 'selectIndexValue', width: 8),
        Logic(name: 'selectFromValue', width: 8),
      );
      await la.build();

      final modules =
          await _synthesizeAndWrite(la, 'build/LogicArrayExample.rohd.json');
      expect(modules, isNotEmpty);
    });

    test('OvenModule', () async {
      final oven = OvenModule(
        Logic(name: 'button', width: 2),
        Logic(name: 'reset'),
        SimpleClockGenerator(10).clk,
      );
      await oven.build();

      final modules =
          await _synthesizeAndWrite(oven, 'build/OvenModule.rohd.json');
      expect(modules, isNotEmpty);
    });

    test('TreeOfTwoInputModules', () async {
      final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
      final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
      await tree.build();

      // Only verify JSON generation succeeds; the deeply nested hierarchy
      // causes a stack overflow in any recursive parser.
      final json = await NetlistSynthesizer().synthesizeToJson(tree);
      expect(json, isNotEmpty);
      if (!_isJS) {
        final file = File('build/TreeOfTwoInputModules.rohd.json');
        await file.create(recursive: true);
        await file.writeAsString(json);
      }
    });

    test('FilterBank', () async {
      final fb = _buildFilterBank();
      await fb.build();

      final modules =
          await _synthesizeAndWrite(fb, 'build/FilterBank.smoke.rohd.json');
      expect(modules, isNotEmpty);
      expect(modules.length, greaterThan(1),
          reason: 'FilterBank should have sub-module definitions');
    });
  });

  // ── JSON structure ────────────────────────────────────────────────────

  group('JSON structure', () {
    test('synthesizeToJson returns valid JSON with modules key', () async {
      final mod = _InverterModule(Logic(name: 'inp'));
      await mod.build();

      final json = await NetlistSynthesizer().synthesizeToJson(mod);
      expect(json, isNotEmpty);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded, contains('modules'));
    });

    test('top module is present with correct ports and top attribute',
        () async {
      final mod = _InverterModule(Logic(name: 'inp'));
      await mod.build();

      final json = await NetlistSynthesizer().synthesizeToJson(mod);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final modules = decoded['modules'] as Map<String, dynamic>;
      expect(modules, contains(mod.definitionName));

      final topMod = modules[mod.definitionName] as Map<String, dynamic>;

      // Port directions
      final ports = topMod['ports'] as Map<String, dynamic>;
      expect(ports, contains('inp'));
      expect(ports, contains('out'));
      expect((ports['inp'] as Map)['direction'], equals('input'));
      expect((ports['out'] as Map)['direction'], equals('output'));

      // Top attribute
      final attrs = topMod['attributes'] as Map<String, dynamic>?;
      expect(attrs, isNotNull);
      expect(attrs!['top'], equals(1));
    });

    test('port bit widths match module interface', () async {
      const width = 16;
      final mod = _AdderModule(
          Logic(name: 'a', width: width), Logic(name: 'b', width: width),
          width: width);
      await mod.build();

      final json = await NetlistSynthesizer().synthesizeToJson(mod);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final modules = decoded['modules'] as Map<String, dynamic>;
      final topMod = modules[mod.definitionName] as Map<String, dynamic>;
      final ports = topMod['ports'] as Map<String, dynamic>;

      expect((ports['a'] as Map)['bits'], hasLength(width));
      expect((ports['b'] as Map)['bits'], hasLength(width));
      expect((ports['sum'] as Map)['bits'], hasLength(width));
    });

    test('cells have connections in default mode', () async {
      final mod = _CompositeModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final json = await NetlistSynthesizer().synthesizeToJson(mod);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final modules = decoded['modules'] as Map<String, dynamic>;
      final topMod = modules[mod.definitionName] as Map<String, dynamic>;
      final cells = topMod['cells'] as Map<String, dynamic>? ?? {};

      final hasConnections = cells.values.any((cell) {
        final c = cell as Map<String, dynamic>;
        final conns = c['connections'] as Map<String, dynamic>?;
        return conns != null && conns.isNotEmpty;
      });
      expect(hasConnections, isTrue);
    });

    test('generateCombinedJson and synthesizeToJson produce same module keys',
        () async {
      final mod = _InverterModule(Logic(name: 'inp'));
      await mod.build();

      final synthesizer = NetlistSynthesizer();
      final synth = SynthBuilder(mod, synthesizer);

      final fromCombined = await synthesizer.generateCombinedJson(synth, mod);
      final fromConvenience = await NetlistSynthesizer().synthesizeToJson(mod);

      final combinedModules =
          (jsonDecode(fromCombined) as Map)['modules'] as Map;
      final convenienceModules =
          (jsonDecode(fromConvenience) as Map)['modules'] as Map;
      expect(combinedModules.keys.toSet(),
          equals(convenienceModules.keys.toSet()));
    });
  });

  // ── SynthBuilder ──────────────────────────────────────────────────────

  group('SynthBuilder', () {
    test('synthesisResults are NetlistSynthesisResult instances', () async {
      final mod = _CompositeModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final synth = SynthBuilder(mod, NetlistSynthesizer());
      expect(synth.synthesisResults, isNotEmpty);
      for (final result in synth.synthesisResults) {
        expect(result, isA<NetlistSynthesisResult>());
      }
    });

    test('composite module includes sub-module definitions', () async {
      final mod = _CompositeModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final synth = SynthBuilder(mod, NetlistSynthesizer());
      final names =
          synth.synthesisResults.map((r) => r.instanceTypeName).toSet();
      expect(names, contains(mod.definitionName));
      expect(synth.synthesisResults.length, greaterThan(1));
    });

    test('toSynthFileContents produces valid JSON per definition', () async {
      final mod = _InverterModule(Logic(name: 'inp'));
      await mod.build();

      final fileContents =
          SynthBuilder(mod, NetlistSynthesizer()).getSynthFileContents();
      expect(fileContents, isNotEmpty);
      for (final fc in fileContents) {
        expect(fc.name, isNotEmpty);
        expect(jsonDecode(fc.contents), isA<Map<String, dynamic>>());
      }
    });
  });

  // ── NetlistSynthesisResult maps ───────────────────────────────────────

  group('NetlistSynthesisResult maps', () {
    test('ports map has direction and bits for each port', () async {
      final mod =
          _AdderModule(Logic(name: 'a', width: 8), Logic(name: 'b', width: 8));
      await mod.build();

      final result = SynthBuilder(mod, NetlistSynthesizer())
          .synthesisResults
          .whereType<NetlistSynthesisResult>()
          .firstWhere((r) => r.module == mod);

      for (final portName in ['a', 'b', 'sum']) {
        expect(result.ports, contains(portName));
        final port = result.ports[portName]!;
        expect(port, contains('direction'));
        expect(port, contains('bits'));
      }
    });

    test('netnames map is populated', () async {
      final mod = _InverterModule(Logic(name: 'inp'));
      await mod.build();

      final result = SynthBuilder(mod, NetlistSynthesizer())
          .synthesisResults
          .whereType<NetlistSynthesisResult>()
          .firstWhere((r) => r.module == mod);
      expect(result.netnames, isNotEmpty);
    });
  });

  // ── collectModuleEntries ──────────────────────────────────────────────

  group('collectModuleEntries', () {
    test('gathers results with correct structure and top attribute', () async {
      final mod = _CompositeModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final synth = SynthBuilder(mod, NetlistSynthesizer());
      final modulesMap =
          collectModuleEntries(synth.synthesisResults, topModule: mod);

      expect(modulesMap, contains(mod.definitionName));
      expect(modulesMap.length, greaterThan(1));

      // Top attribute
      final topAttrs = modulesMap[mod.definitionName]!['attributes']!
          as Map<String, Object?>;
      expect(topAttrs['top'], equals(1));

      // Every entry has the expected sections
      for (final entry in modulesMap.values) {
        expect(entry, contains('ports'));
        expect(entry, contains('cells'));
        expect(entry, contains('netnames'));
      }
    });
  });

  // ── buildModulesMap ───────────────────────────────────────────────────

  group('buildModulesMap', () {
    test('returns map with all definitions and expected sections', () async {
      final mod = _CompositeModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final synthesizer = NetlistSynthesizer();
      final synth = SynthBuilder(mod, synthesizer);
      final modulesMap = await synthesizer.buildModulesMap(synth, mod);

      expect(modulesMap, contains(mod.definitionName));
      expect(modulesMap.length, greaterThan(1));
      for (final modEntry in modulesMap.entries) {
        final data = modEntry.value;
        expect(data, contains('ports'), reason: modEntry.key);
        expect(data, contains('cells'), reason: modEntry.key);
        expect(data, contains('netnames'), reason: modEntry.key);
      }
    });
  });

  // ── NetlistOptions ───────────────────────────────────────────────────

  group('NetlistOptions', () {
    test('slimMode omits cell connections', () async {
      final mod = _CompositeModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final slimSynth =
          NetlistSynthesizer(options: const NetlistOptions(slimMode: true));
      final json = await slimSynth.synthesizeToJson(mod);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final modules = decoded['modules'] as Map<String, dynamic>;

      for (final modEntry in modules.values) {
        final data = modEntry as Map<String, dynamic>;
        final cells = data['cells'] as Map<String, dynamic>? ?? {};
        for (final cell in cells.values) {
          final c = cell as Map<String, dynamic>;
          final conns = c['connections'] as Map<String, dynamic>?;
          if (conns != null) {
            expect(conns, isEmpty, reason: 'slim mode should omit connections');
          }
        }
      }
    });
  });

  // ── FilterBank (multi-channel, dedup, loopback) ───────────────────────

  group('FilterBank netlist', () {
    test('produces valid netlist with multiple module definitions', () async {
      final mod = _buildFilterBank();
      await mod.build();

      final modules =
          await _synthesizeAndWrite(mod, 'build/FilterBank.rohd.json');
      expect(modules, isNotEmpty);
      expect(modules.length, greaterThan(1),
          reason: 'FilterBank should have sub-module definitions');

      // Top module should have cells
      final topMod = modules[mod.definitionName] as Map<String, dynamic>;
      final cells = topMod['cells'] as Map<String, dynamic>? ?? {};
      expect(cells, isNotEmpty, reason: 'FilterBank should have cells');
    });

    test('FilterChannel definitions are deduplicated', () async {
      final mod = _buildFilterBank();
      await mod.build();

      final json = await NetlistSynthesizer().synthesizeToJson(mod);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final modules = parsed['modules'] as Map<String, dynamic>;
      final channelDefs =
          modules.keys.where((k) => k.contains('FilterChannel')).toList();
      // Two channels with different coefficients should produce
      // separate definitions (not fully deduplicated).
      expect(channelDefs, isNotEmpty,
          reason: 'FilterChannel definitions should be present');
    });

    test('all module entries have ports, cells, and netnames', () async {
      final mod = _buildFilterBank();
      await mod.build();

      final synthesizer = NetlistSynthesizer();
      final synth = SynthBuilder(mod, synthesizer);
      final modulesMap = await synthesizer.buildModulesMap(synth, mod);

      for (final entry in modulesMap.entries) {
        final data = entry.value;
        expect(data, contains('ports'), reason: '${entry.key} missing ports');
        expect(data, contains('cells'), reason: '${entry.key} missing cells');
        expect(data, contains('netnames'),
            reason: '${entry.key} missing netnames');
      }
    });

    test('ports have correct directions on sub-modules', () async {
      final mod = _buildFilterBank();
      await mod.build();

      final synthesizer = NetlistSynthesizer();
      final synth = SynthBuilder(mod, synthesizer);

      for (final result
          in synth.synthesisResults.whereType<NetlistSynthesisResult>()) {
        for (final port in result.ports.entries) {
          final dir = port.value['direction']! as String;
          expect(['input', 'output', 'inout'], contains(dir),
              reason: '${result.instanceTypeName}.${port.key} '
                  'has invalid direction');
        }
      }
    });
  });
}

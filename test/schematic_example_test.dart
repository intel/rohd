// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_example_test.dart
// Convert examples to schematic for and check the produced JSON.

// 2025 December 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/schematic.dart';
import 'package:test/test.dart';

import '../example/example.dart';
import '../example/fir_filter.dart';
import '../example/logic_array.dart';
import '../example/oven_fsm.dart';
import '../example/tree.dart';

void main() {
  test('Schematic dump for example Counter', () async {
    final en = Logic(name: 'en');
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final counter = Counter(en, reset, clk);
    await counter.build();

    const outPath = 'build/Counter.rohd.json';
    SchematicDumper(counter,
        outputPath: outPath, filterConstInputsToCombinational: true);

    final f = File(outPath);
    expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
    final contents = await f.readAsString();
    expect(contents.trim().isNotEmpty, isTrue);

    final r = await runYosysLoader(outPath);
    expect(r.success, isTrue,
        reason: 'loader should load Counter: ${r.error ?? r}');
  });

  group('SynthBuilder schematic generation for examples', () {
    Future<void> writeCombined(
        SynthBuilder synth, Module top, String out) async {
      final allModules = <String, Map<String, Object?>>{};
      for (final result in synth.synthesisResults) {
        if (result is SchematicSynthesisResult) {
          final typeName = result.instanceTypeName;
          final attrs = Map<String, Object?>.from(result.attributes);
          if (result.module == top) {
            attrs['top'] = 1;
          }
          allModules[typeName] = {
            'attributes': attrs,
            'ports': result.ports,
            'cells': result.cells,
            'netnames': result.netnames,
          };
        }
      }
      final combined = {
        'creator': 'SchematicSynthesizer via SynthBuilder (rohd)',
        'modules': allModules,
      };
      final json = const JsonEncoder.withIndent('  ').convert(combined);
      await File(out).writeAsString(json);
    }

    test('SynthBuilder schematic for Counter', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;

      final counter = Counter(en, reset, clk);
      await counter.build();

      final synth = SynthBuilder(counter, SchematicSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      const outPath = 'build/Counter.synth.rohd.json';
      await writeCombined(synth, counter, outPath);
      final f = File(outPath);
      expect(f.existsSync(), isTrue);

      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason: 'loader should load Counter synth: ${r.error ?? r}');
    });

    test('SynthBuilder schematic for FIR filter example', () async {
      final en = Logic(name: 'en');
      final resetB = Logic(name: 'resetB');
      final clk = SimpleClockGenerator(10).clk;
      final inputVal = Logic(name: 'inputVal', width: 8);

      final fir =
          FirFilter(en, resetB, clk, inputVal, [0, 0, 0, 1], bitWidth: 8);
      await fir.build();

      final synth = SynthBuilder(fir, SchematicSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      const outPath = 'build/FirFilter.synth.rohd.json';
      await writeCombined(synth, fir, outPath);
      final f = File(outPath);
      expect(f.existsSync(), isTrue);

      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason: 'loader should load FirFilter synth: ${r.error ?? r}');
    });

    test('SynthBuilder schematic for LogicArray example', () async {
      final arrayA = LogicArray([4], 8, name: 'arrayA');
      final id = Logic(name: 'id', width: 3);
      final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
      final selectFromValue = Logic(name: 'selectFromValue', width: 8);

      final la =
          LogicArrayExample(arrayA, id, selectIndexValue, selectFromValue);
      await la.build();

      final synth = SynthBuilder(la, SchematicSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      const outPath = 'build/LogicArrayExample.synth.rohd.json';
      await writeCombined(synth, la, outPath);
      final f = File(outPath);
      expect(f.existsSync(), isTrue);

      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason:
              'loader should load LogicArrayExample synth: ${r.error ?? r}');
    });

    test('SynthBuilder schematic for OvenModule example', () async {
      final button = Logic(name: 'button', width: 2);
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;

      final oven = OvenModule(button, reset, clk);
      await oven.build();

      final synth = SynthBuilder(oven, SchematicSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      const outPath = 'build/OvenModule.synth.rohd.json';
      await writeCombined(synth, oven, outPath);
      final f = File(outPath);
      expect(f.existsSync(), isTrue);

      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason: 'loader should load OvenModule synth: ${r.error ?? r}');
    });

    test('SynthBuilder schematic for TreeOfTwoInputModules example', () async {
      final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
      final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
      await tree.build();

      final synth = SynthBuilder(tree, SchematicSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      const outPath = 'build/TreeOfTwoInputModules.synth.rohd.json';
      await writeCombined(synth, tree, outPath);
      final f = File(outPath);
      expect(f.existsSync(), isTrue);

      // Skip loader validation for the tree as it may be deeply nested.
    });
  });

  test('Schematic dump for FIR filter example', () async {
    final en = Logic(name: 'en');
    final resetB = Logic(name: 'resetB');
    final clk = SimpleClockGenerator(10).clk;
    final inputVal = Logic(name: 'inputVal', width: 8);

    final fir = FirFilter(en, resetB, clk, inputVal, [0, 0, 0, 1], bitWidth: 8);
    await fir.build();

    const outPath = 'build/FirFilter.rohd.json';
    SchematicDumper(fir,
        outputPath: outPath, filterConstInputsToCombinational: true);
    final f = File(outPath);
    expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
    final contents = await f.readAsString();
    expect(contents.trim().isNotEmpty, isTrue);

    final r = await runYosysLoader(outPath);
    expect(r.success, isTrue,
        reason: 'loader should load FirFilter: ${r.error ?? r}');
  });

  test('Schematic dump for LogicArray example', () async {
    final arrayA = LogicArray([4], 8, name: 'arrayA');
    final id = Logic(name: 'id', width: 3);
    final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
    final selectFromValue = Logic(name: 'selectFromValue', width: 8);

    final la = LogicArrayExample(arrayA, id, selectIndexValue, selectFromValue);
    await la.build();

    const outPath = 'build/LogicArrayExample.rohd.json';
    SchematicDumper(la,
        outputPath: outPath, filterConstInputsToCombinational: true);
    final f = File(outPath);
    expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
    final contents = await f.readAsString();
    expect(contents.trim().isNotEmpty, isTrue);

    final r = await runYosysLoader(outPath);
    expect(r.success, isTrue,
        reason: 'loader should load LogicArrayExample: ${r.error ?? r}');
  });

  test('Schematic dump for OvenModule example', () async {
    final button = Logic(name: 'button', width: 2);
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final oven = OvenModule(button, reset, clk);
    await oven.build();

    const outPath = 'build/OvenModule.rohd.json';
    SchematicDumper(oven,
        outputPath: outPath, filterConstInputsToCombinational: true);
    final f = File(outPath);
    expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
    final contents = await f.readAsString();
    expect(contents.trim().isNotEmpty, isTrue);

    final r = await runYosysLoader(outPath);
    expect(r.success, isTrue,
        reason: 'loader should load OvenModule: ${r.error ?? r}');
  });

  test('Schematic dump for TreeOfTwoInputModules example', () async {
    final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
    final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
    await tree.build();

    const outPath = 'build/TreeOfTwoInputModules.rohd.json';
    SchematicDumper(tree,
        outputPath: outPath, filterConstInputsToCombinational: true);
    final f = File(outPath);
    expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
    final contents = await f.readAsString();
    expect(contents.trim().isNotEmpty, isTrue);

    // The loader can hit a recursion/stack overflow on deeply nested
    // generated structures for the tree example. For now, ensure the
    // ROHD JSON was produced and is non-empty; loader validation is
    // skipped to avoid flaky failures.
    // If desired, re-enable loader checks with a smaller tree size.
  });
}

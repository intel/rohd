// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_example_test.dart
// Convert examples to schematic for and check the produced JSON.

// 2025 December 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

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
  // Detect whether running in JS (dart2js) environment. In JS many
  // `dart:io` APIs are unsupported; when running tests with
  // `--platform node` we skip filesystem and loader assertions.
  const isJS = identical(0, 0.0);

  // Tests should call the synthesizer API directly to obtain the final
  // combined JSON string and perform VM-only writes themselves.

  // Helper used by the tests to synthesize `top` and optionally write the
  // produced JSON to `outPath` when running on VM. Returns the JSON string
  // so callers can validate loader compatibility.
  Future<YosysLoaderResult> convertTestWriteSchematic(
      Module top, String outPath) async {
    final synth = SynthBuilder(top, SchematicSynthesizer());
    final json =
        await (synth.synthesizer as SchematicSynthesizer).synthesizeToJson(top);
    if (!isJS) {
      final file = File(outPath);
      await file.create(recursive: true);
      await file.writeAsString(json);
    }
    return runYosysLoaderFromString(json);
  }

  test('Schematic dump for example Counter', () async {
    final en = Logic(name: 'en');
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final counter = Counter(en, reset, clk);
    await counter.build();
    counter.generateSynth();

    final r =
        await convertTestWriteSchematic(counter, 'build/Counter.rohd.json');

    expect(
      r.success,
      isTrue,
      reason: 'loader should load Counter from string: ${r.error ?? r}',
    );
  });

  group('SynthBuilder schematic generation for examples', () {
    test('SynthBuilder schematic for Counter', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;

      final counter = Counter(en, reset, clk);
      await counter.build();

      final r = await convertTestWriteSchematic(
          counter, 'build/Counter.synth.rohd.json');
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

      final r = await convertTestWriteSchematic(
          fir, 'build/FirFilter.synth.rohd.json');
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

      final r = await convertTestWriteSchematic(
          la, 'build/LogicArrayExample.synth.rohd.json');
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

      final r = await convertTestWriteSchematic(
          oven, 'build/OvenModule.synth.rohd.json');
      expect(r.success, isTrue,
          reason: 'loader should load OvenModule synth: ${r.error ?? r}');
    });

    test('SynthBuilder schematic for TreeOfTwoInputModules example', () async {
      final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
      final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
      await tree.build();

      final synth = SynthBuilder(tree, SchematicSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      final r = await convertTestWriteSchematic(
          tree, 'build/TreeOfTwoInputModules.synth.rohd.json');
      expect(r.success, isTrue,
          reason: 'loader should load TreeOfTwoInputModules synth: '
              '${r.error ?? r}');
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
    final rStr = await convertTestWriteSchematic(fir, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason: 'loader should load FirFilter: ${r.error ?? r}');
    } else {
      expect(
        rStr.success,
        isTrue,
        reason:
            'loader should load FirFilter from string: ${rStr.error ?? rStr}',
      );
    }
  });

  test('Schematic dump for LogicArray example', () async {
    final arrayA = LogicArray([4], 8, name: 'arrayA');
    final id = Logic(name: 'id', width: 3);
    final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
    final selectFromValue = Logic(name: 'selectFromValue', width: 8);

    final la = LogicArrayExample(arrayA, id, selectIndexValue, selectFromValue);
    await la.build();

    const outPath = 'build/LogicArrayExample.rohd.json';
    final rStr = await convertTestWriteSchematic(la, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason: 'loader should load LogicArrayExample: ${r.error ?? r}');
    } else {
      expect(
        rStr.success,
        isTrue,
        reason: 'loader should load LogicArrayExample from string: '
            '${rStr.error ?? rStr}',
      );
    }
  });

  test('Schematic dump for OvenModule example', () async {
    final button = Logic(name: 'button', width: 2);
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final oven = OvenModule(button, reset, clk);
    await oven.build();

    const outPath = 'build/OvenModule.rohd.json';
    final rStr = await convertTestWriteSchematic(oven, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
      final r = await runYosysLoader(outPath);
      expect(r.success, isTrue,
          reason: 'loader should load OvenModule: ${r.error ?? r}');
    } else {
      expect(
        rStr.success,
        isTrue,
        reason:
            'loader should load OvenModule from string: ${rStr.error ?? rStr}',
      );
    }
  });

  test('Schematic dump for TreeOfTwoInputModules example', () async {
    final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
    final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
    await tree.build();

    const outPath = 'build/TreeOfTwoInputModules.rohd.json';
    final rStr = await convertTestWriteSchematic(tree, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    } else {
      expect(rStr.success, isTrue,
          reason: 'loader should load TreeOfTwoInputModules from string: '
              '${rStr.error ?? rStr}');
    }
  });
}

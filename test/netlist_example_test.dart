// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_example_test.dart
// Convert examples to netlist JSON and check the produced output.

// 2026 March 31
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
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

  // Helper used by the tests to synthesize `top` and optionally write the
  // produced JSON to `outPath` when running on VM. Returns the decoded
  // modules map from the Yosys-format JSON.
  Future<Map<String, dynamic>> convertTestWriteNetlist(
    Module top,
    String outPath,
  ) async {
    final synth = SynthBuilder(top, NetlistSynthesizer());
    final jsonStr =
        await (synth.synthesizer as NetlistSynthesizer).synthesizeToJson(top);
    if (!isJS) {
      final file = File(outPath);
      await file.create(recursive: true);
      await file.writeAsString(jsonStr);
    }
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    return decoded['modules'] as Map<String, dynamic>;
  }

  test('Netlist dump for example Counter', () async {
    final en = Logic(name: 'en');
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final counter = Counter(en, reset, clk);
    await counter.build();
    counter.generateSynth();

    final modules = await convertTestWriteNetlist(
      counter,
      'build/Counter.rohd.json',
    );

    expect(
      modules,
      isNotEmpty,
      reason: 'Counter netlist should have module definitions',
    );
    // The top module should have cells (sub-module instances or gates)
    final topMod = modules[counter.definitionName] as Map<String, dynamic>;
    final cells = topMod['cells'] as Map<String, dynamic>? ?? {};
    expect(cells, isNotEmpty, reason: 'Counter should have cells');
  });

  group('SynthBuilder netlist generation for examples', () {
    test('SynthBuilder netlist for Counter', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;

      final counter = Counter(en, reset, clk);
      await counter.build();

      final modules = await convertTestWriteNetlist(
        counter,
        'build/Counter.synth.rohd.json',
      );
      expect(
        modules,
        isNotEmpty,
        reason: 'Counter synth netlist should have modules',
      );
    });

    test('SynthBuilder netlist for FIR filter example', () async {
      final en = Logic(name: 'en');
      final resetB = Logic(name: 'resetB');
      final clk = SimpleClockGenerator(10).clk;
      final inputVal = Logic(name: 'inputVal', width: 8);

      final fir =
          FirFilter(en, resetB, clk, inputVal, [0, 0, 0, 1], bitWidth: 8);
      await fir.build();

      final synth = SynthBuilder(fir, NetlistSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      final modules = await convertTestWriteNetlist(
        fir,
        'build/FirFilter.synth.rohd.json',
      );
      expect(
        modules,
        isNotEmpty,
        reason: 'FirFilter synth netlist should have modules',
      );
    });

    test('SynthBuilder netlist for LogicArray example', () async {
      final arrayA = LogicArray([4], 8, name: 'arrayA');
      final id = Logic(name: 'id', width: 3);
      final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
      final selectFromValue = Logic(name: 'selectFromValue', width: 8);

      final la = LogicArrayExample(
        arrayA,
        id,
        selectIndexValue,
        selectFromValue,
      );
      await la.build();

      final synth = SynthBuilder(la, NetlistSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      final modules = await convertTestWriteNetlist(
        la,
        'build/LogicArrayExample.synth.rohd.json',
      );
      expect(
        modules,
        isNotEmpty,
        reason: 'LogicArrayExample synth netlist should have modules',
      );
    });

    test('SynthBuilder netlist for OvenModule example', () async {
      final button = Logic(name: 'button', width: 2);
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;

      final oven = OvenModule(button, reset, clk);
      await oven.build();

      final synth = SynthBuilder(oven, NetlistSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      final modules = await convertTestWriteNetlist(
        oven,
        'build/OvenModule.synth.rohd.json',
      );
      expect(
        modules,
        isNotEmpty,
        reason: 'OvenModule synth netlist should have modules',
      );
    });

    test('SynthBuilder netlist for TreeOfTwoInputModules example', () async {
      final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
      final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
      await tree.build();

      final synth = SynthBuilder(tree, NetlistSynthesizer());
      expect(synth.synthesisResults.isNotEmpty, isTrue);

      // Only verify JSON generation succeeds; the deeply nested hierarchy
      // causes a stack overflow in any recursive parser (pure Dart or JS).
      final json = await (synth.synthesizer as NetlistSynthesizer)
          .synthesizeToJson(tree);
      expect(
        json,
        isNotEmpty,
        reason: 'TreeOfTwoInputModules should produce non-empty JSON',
      );
      if (!isJS) {
        final file = File('build/TreeOfTwoInputModules.synth.rohd.json');
        await file.create(recursive: true);
        await file.writeAsString(json);
      }
    });
  });

  test('Netlist dump for FIR filter example', () async {
    final en = Logic(name: 'en');
    final resetB = Logic(name: 'resetB');
    final clk = SimpleClockGenerator(10).clk;
    final inputVal = Logic(name: 'inputVal', width: 8);

    final fir = FirFilter(en, resetB, clk, inputVal, [0, 0, 0, 1], bitWidth: 8);
    await fir.build();

    const outPath = 'build/FirFilter.rohd.json';
    final modules = await convertTestWriteNetlist(fir, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    }
    expect(
      modules,
      isNotEmpty,
      reason: 'FirFilter netlist should have module definitions',
    );
  });

  test('Netlist dump for LogicArray example', () async {
    final arrayA = LogicArray([4], 8, name: 'arrayA');
    final id = Logic(name: 'id', width: 3);
    final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
    final selectFromValue = Logic(name: 'selectFromValue', width: 8);

    final la = LogicArrayExample(arrayA, id, selectIndexValue, selectFromValue);
    await la.build();

    const outPath = 'build/LogicArrayExample.rohd.json';
    final modules = await convertTestWriteNetlist(la, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    }
    expect(
      modules,
      isNotEmpty,
      reason: 'LogicArrayExample netlist should have module definitions',
    );
  });

  test('Netlist dump for OvenModule example', () async {
    final button = Logic(name: 'button', width: 2);
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final oven = OvenModule(button, reset, clk);
    await oven.build();

    const outPath = 'build/OvenModule.rohd.json';
    final modules = await convertTestWriteNetlist(oven, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    }
    expect(
      modules,
      isNotEmpty,
      reason: 'OvenModule netlist should have module definitions',
    );
  });

  test('Netlist dump for TreeOfTwoInputModules example', () async {
    final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
    final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
    await tree.build();

    // Only verify JSON generation succeeds; the deeply nested hierarchy
    // causes a stack overflow in any recursive parser.
    const outPath = 'build/TreeOfTwoInputModules.rohd.json';
    final synth = SynthBuilder(tree, NetlistSynthesizer());
    final json =
        await (synth.synthesizer as NetlistSynthesizer).synthesizeToJson(tree);
    expect(
      json,
      isNotEmpty,
      reason: 'TreeOfTwoInputModules should produce non-empty JSON',
    );
    if (!isJS) {
      final file = File(outPath);
      await file.create(recursive: true);
      await file.writeAsString(json);
      expect(file.existsSync(), isTrue, reason: 'ROHD JSON should be created');
    }
  });
}

// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_example_test.dart
// Convert examples to netlist JSON and check the produced output.

// 2025 December 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
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
  // produced JSON to `outPath` when running on VM. Validates the JSON by
  // parsing it through the pure-Dart NetlistHierarchyAdapter.
  Future<NetlistHierarchyAdapter> convertTestWriteNetlist(
    Module top,
    String outPath,
  ) async {
    final synth = SynthBuilder(top, NetlistSynthesizer());
    final json =
        await (synth.synthesizer as NetlistSynthesizer).synthesizeToJson(top);
    if (!isJS) {
      final file = File(outPath);
      await file.create(recursive: true);
      await file.writeAsString(json);
    }
    return NetlistHierarchyAdapter.fromJson(json);
  }

  test('Netlist dump for example Counter', () async {
    final en = Logic(name: 'en');
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final counter = Counter(en, reset, clk);
    await counter.build();
    counter.generateSynth();

    final adapter = await convertTestWriteNetlist(
      counter,
      'build/Counter.rohd.json',
    );

    expect(
      adapter.root.children,
      isNotEmpty,
      reason: 'Counter hierarchy should have children',
    );
  });

  group('SynthBuilder netlist generation for examples', () {
    test('SynthBuilder netlist for Counter', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;

      final counter = Counter(en, reset, clk);
      await counter.build();

      final adapter = await convertTestWriteNetlist(
        counter,
        'build/Counter.synth.rohd.json',
      );
      expect(
        adapter.root.name,
        isNotEmpty,
        reason: 'Counter synth hierarchy should have a root name',
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

      final adapter = await convertTestWriteNetlist(
        fir,
        'build/FirFilter.synth.rohd.json',
      );
      expect(
        adapter.root.name,
        isNotEmpty,
        reason: 'FirFilter synth hierarchy should have a root name',
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

      final adapter = await convertTestWriteNetlist(
        la,
        'build/LogicArrayExample.synth.rohd.json',
      );
      expect(
        adapter.root.name,
        isNotEmpty,
        reason: 'LogicArrayExample synth hierarchy should have a root name',
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

      final adapter = await convertTestWriteNetlist(
        oven,
        'build/OvenModule.synth.rohd.json',
      );
      expect(
        adapter.root.name,
        isNotEmpty,
        reason: 'OvenModule synth hierarchy should have a root name',
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
    final adapter = await convertTestWriteNetlist(fir, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    }
    expect(
      adapter.root.children,
      isNotEmpty,
      reason: 'FirFilter hierarchy should have children',
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
    final adapter = await convertTestWriteNetlist(la, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    }
    expect(
      adapter.root.children,
      isNotEmpty,
      reason: 'LogicArrayExample hierarchy should have children',
    );
  });

  test('Netlist dump for OvenModule example', () async {
    final button = Logic(name: 'button', width: 2);
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final oven = OvenModule(button, reset, clk);
    await oven.build();

    const outPath = 'build/OvenModule.rohd.json';
    final adapter = await convertTestWriteNetlist(oven, outPath);
    if (!isJS) {
      final f = File(outPath);
      expect(f.existsSync(), isTrue, reason: 'ROHD JSON should be created');
      final contents = await f.readAsString();
      expect(contents.trim().isNotEmpty, isTrue);
    }
    expect(
      adapter.root.children,
      isNotEmpty,
      reason: 'OvenModule hierarchy should have children',
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

  // ── Design API tests ─────────────────────────────────────────────────
  //
  // These exercise the production path: build(netlistOptions: ...) →
  // ModuleTree.instance.toJson() which produces the unified JSON format
  // {"hierarchy": {...}, "netlist": {"modules": {...}}} consumed by DevTools.

  group('Design API unified netlist generation', () {
    tearDown(() async {
      await Simulator.reset();
      ModuleTree.clearCustomNetlistJson();
    });

    /// Build [module] with synthesis, write the unified JSON, and validate
    /// that both hierarchy and netlist sections are present and parseable.
    Future<void> validateDesignApi(
      Module module,
      String outPath, {
      NetlistOptions? options,
    }) async {
      await module.build(netlistOptions: options ?? const NetlistOptions());

      // ── Full netlist (with connections) ────────────────────────────
      final fullJson = ModuleTree.instance.toFullNetlistJson();
      expect(fullJson, isNotNull,
          reason: 'toFullNetlistJson should not be null');
      final full = jsonDecode(fullJson!) as Map<String, dynamic>;

      expect(
        full.containsKey('netlist'),
        isTrue,
        reason: 'Full JSON should have netlist section',
      );

      final netlistSection = full['netlist'] as Map<String, dynamic>;
      expect(
        netlistSection.containsKey('modules'),
        isTrue,
        reason: 'Netlist section should have modules',
      );
      final modules = netlistSection['modules'] as Map<String, dynamic>;
      expect(
        modules,
        isNotEmpty,
        reason: 'Netlist should contain at least one module',
      );

      // Verify cells have connections (the key difference from slim)
      final topModule = modules.values.first as Map<String, dynamic>;
      final cells = topModule['cells'] as Map<String, dynamic>? ?? {};
      if (cells.isNotEmpty) {
        final hasConnections = cells.values.any((cell) {
          final c = cell as Map<String, dynamic>;
          final conns = c['connections'] as Map<String, dynamic>?;
          return conns != null && conns.isNotEmpty;
        });
        expect(
          hasConnections,
          isTrue,
          reason: 'Full netlist cells should have connections',
        );
      }

      // Verify the netlist section parses through hierarchy adapter
      final adapter = NetlistHierarchyAdapter.fromMap(netlistSection);
      expect(
        adapter.root.children,
        isNotEmpty,
        reason: '${module.definitionName} should have hierarchy children',
      );

      // ── Slim netlist (no connections, for incremental loading) ─────
      final slimJson = ModuleTree.instance.toModuleSignalJson();
      expect(slimJson, isNotNull,
          reason: 'toModuleSignalJson should not be null');
      final slim = jsonDecode(slimJson!) as Map<String, dynamic>;
      expect(
        slim.containsKey('netlist'),
        isTrue,
        reason: 'Slim JSON should have netlist section',
      );

      // ── Module count parity between full and slim ─────────────────
      final slimNetlist = slim['netlist'] as Map<String, dynamic>;
      final slimModules = slimNetlist['modules'] as Map<String, dynamic>;
      expect(
        slimModules.length,
        equals(modules.length),
        reason: 'Slim and full should have same number of modules',
      );

      // Write the full unified JSON for inspection
      if (!isJS) {
        final file = File(outPath);
        await file.create(recursive: true);
        await file.writeAsString(fullJson);
      }
    }

    test('Counter via design API', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;
      final counter = Counter(en, reset, clk);

      await validateDesignApi(counter, 'build/Counter.design.rohd.json');
    });

    test('FIR filter via design API', () async {
      final en = Logic(name: 'en');
      final resetB = Logic(name: 'resetB');
      final clk = SimpleClockGenerator(10).clk;
      final inputVal = Logic(name: 'inputVal', width: 8);
      final fir = FirFilter(
          en,
          resetB,
          clk,
          inputVal,
          [
            0,
            0,
            0,
            1,
          ],
          bitWidth: 8);

      await validateDesignApi(fir, 'build/FirFilter.design.rohd.json');
    });

    test('LogicArray via design API', () async {
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

      await validateDesignApi(la, 'build/LogicArrayExample.design.rohd.json');
    });

    test('OvenModule via design API', () async {
      final button = Logic(name: 'button', width: 2);
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;
      final oven = OvenModule(button, reset, clk);

      await validateDesignApi(oven, 'build/OvenModule.design.rohd.json');
    });

    test('TreeOfTwoInputModules via design API', () async {
      final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
      final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));

      await tree.build(netlistOptions: const NetlistOptions());

      final fullJson = ModuleTree.instance.toFullNetlistJson();
      expect(fullJson, isNotNull);
      final unified = jsonDecode(fullJson!) as Map<String, dynamic>;

      expect(unified.containsKey('netlist'), isTrue);

      final netlistSection = unified['netlist'] as Map<String, dynamic>;
      final modules = netlistSection['modules'] as Map<String, dynamic>;
      expect(modules, isNotEmpty, reason: 'Tree netlist should have modules');

      if (!isJS) {
        final file = File('build/TreeOfTwoInputModules.design.rohd.json');
        await file.create(recursive: true);
        await file.writeAsString(fullJson);
      }
    });
  });
}

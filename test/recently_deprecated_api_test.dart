// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

// Compatibility tests intentionally exercise the retained deprecated APIs.
// ignore_for_file: deprecated_member_use_from_same_package

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/diagnostics/inspector_service.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_synthesis_result.dart';
import 'package:test/test.dart';

class _CompatibilityModule extends Module {
  _CompatibilityModule(Logic source) : super(name: 'compatibility') {
    final a = addInput('a', source);
    addOutput('b') <= ~a;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('recently deprecated synthesis API delegates to current output',
      () async {
    final mod = _CompatibilityModule(Logic());
    await mod.build();

    String withoutTimestamp(String output) => output
        .split('\n')
        .where((line) => !line.contains('* Generation time:'))
        .join('\n');
    expect(
      withoutTimestamp(mod.generateSynth()),
      withoutTimestamp(mod.dumpSystemVerilog()),
    );
  });

  test('released hierarchy spelling remains a compatible alias', () async {
    final mod = _CompatibilityModule(Logic());
    await mod.build();

    expect(
        ModuleTree.instance.hierarchyJSON, ModuleTree.instance.hierarchyJson);
  });

  test('netlist API first released in 0.6.11 retains artifact contents',
      () async {
    final mod = _CompatibilityModule(Logic());
    await mod.build();
    final result = SynthBuilder(mod, NetlistSynthesizer())
        .synthesisResults
        .whereType<NetlistSynthesisResult>()
        .single;

    expect(
        result.toFileContents(), result.toSynthFileContents().single.contents);
  });

  test('pair interface modify and clone constructor remain compatible', () {
    String prefixed(String original) => 'x_$original';
    final source = PairInterface(
      portsFromConsumer: [Logic(name: 'a')],
      portsFromProvider: [Logic(name: 'b')],
      modify: prefixed,
    );

    final copy = PairInterface.clone(source);

    expect(copy.modify, same(prefixed));
    expect(copy.ports.keys, unorderedEquals(['a', 'b']));
  });

  test('released waveform wrapper still captures VCD', () async {
    final directory =
        Directory.systemTemp.createTempSync('rohd_compatibility_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = Logic()..put(0);
    final mod = _CompatibilityModule(source);
    await mod.build();
    final outputPath = '${directory.path}/waves.vcd';

    final dumper = WaveDumper(mod, outputPath: outputPath);
    final currentPath = '${directory.path}/current.vcd';
    mod.dumpWaves(outputPath: currentPath);
    expect(dumper.module, same(mod));
    expect(dumper.outputPath, outputPath);

    Simulator.registerAction(5, () => source.put(1));
    Simulator.setMaxSimTime(10);
    await Simulator.run();

    final contents = File(outputPath).readAsStringSync();
    expect(contents, contains(r'$enddefinitions'));
    expect(contents, contains('#5'));
    String withoutDate(String output) =>
        output.replaceFirst(RegExp(r'\$date[\s\S]*?\$end'), '');
    expect(withoutDate(contents),
        withoutDate(File(currentPath).readAsStringSync()));
  });
}

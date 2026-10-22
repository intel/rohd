// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
// Compatibility tests intentionally exercise the retained deprecated APIs.
// ignore_for_file: deprecated_member_use_from_same_package
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

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

class _CompatibilityPairModule extends Module {
  _CompatibilityPairModule(PairInterface source,
      {String Function(String original)? uniquify}) {
    source
        .clone()
        .pairConnectIO(this, source, PairRole.provider, uniquify: uniquify);
  }
}

class _LegacyCustomSvModule extends Module with CustomSystemVerilog {
  _LegacyCustomSvModule(Logic source) : super(name: 'legacy_custom_sv') {
    final a = addInput('a', source);
    addOutput('b') <= a;
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> inputs,
    Map<String, String> outputs,
  ) =>
      'assign ${outputs['b']} = ~${inputs['a']}; // $instanceType $instanceName';
}

class _LegacyCustomSvWrap extends Module {
  _LegacyCustomSvWrap(Logic source) {
    final input = addInput('a', source);
    final child = _LegacyCustomSvModule(input);
    addOutput('b') <= child.outputs['b']!;
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

  test('transitional synthesis aliases delegate to current APIs', () async {
    final mod = _CompatibilityModule(Logic());
    await mod.build();
    final builder = SynthBuilder(mod, SystemVerilogSynthesizer());

    expect(builder.top, same(mod));
    expect(
      builder.getFileContents(),
      builder.getSynthFileContents().map((contents) => contents.contents),
    );
    final result = builder.synthesisResults.single;
    expect(
      result.toFileContents(),
      result.toSynthFileContents().single.contents,
    );
    for (final result
        in SynthBuilder(mod, SystemCSynthesizer()).synthesisResults) {
      expect(
        result.toFileContents(),
        result.toSynthFileContents().single.contents,
      );
    }
  });

  test('deprecated Port and LogicStructure aliases remain usable', () {
    final port = Port('legacy_port', 2);
    expect(port.name, 'legacy_port');
    expect(port.width, 2);

    final structure = LogicStructure([Logic()..put(1)]);
    expect(structure.bit, structure.value);
  });

  test('legacy custom SystemVerilog APIs still delegate', () {
    final module = _LegacyCustomSvModule(Logic());
    final synthesizer = SystemVerilogSynthesizer();

    expect(synthesizer.generatesDefinition(module), isFalse);
    expect(
      SystemVerilogSynthesizer.instantiationVerilogFor(
        module: module,
        instanceType: 'Legacy',
        instanceName: 'instance',
        ports: {'a': 'source', 'b': 'sink'},
      ),
      'assign sink = ~source; // Legacy instance',
    );
  });

  test('deprecated custom SystemVerilog mixin still generates instances',
      () async {
    final mod = _LegacyCustomSvWrap(Logic());
    await mod.build();

    expect(
      mod.dumpSystemVerilog(),
      contains('assign b = ~a; // *NONE* legacy_custom_sv'),
    );
  });

  test('deprecated SystemVerilog instantiation helper forwards arguments',
      () async {
    final mod = _CompatibilityModule(Logic());
    await mod.build();
    final legacy = SystemVerilogSynthesizer.instantiationVerilogWithParameters(
      mod,
      'Compatibility',
      'instance',
      {'a': 'source'},
      {'b': 'sink'},
    );
    final current = SystemVerilogSynthesizer.instantiationVerilogFor(
      module: mod,
      instanceType: 'Compatibility',
      instanceName: 'instance',
      ports: {'a': 'source', 'b': 'sink'},
    );

    expect(legacy, current);
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
    expect(source.clone().modify, same(prefixed));
  });

  for (final uniquify in [false, true]) {
    test('pair interface modify composes with uniquify=$uniquify', () async {
      final source = PairInterface(
        portsFromConsumer: [Logic(name: 'a')..put(1)],
        portsFromProvider: [Logic(name: 'b')],
        modify: (original) => 'legacy_$original',
      );
      final module = _CompatibilityPairModule(source,
          uniquify: uniquify ? (original) => 'outer_$original' : null);
      await module.build();

      final prefix = uniquify ? 'outer_legacy_' : 'legacy_';
      expect(module.inputs.keys, ['${prefix}a']);
      expect(module.outputs.keys, ['${prefix}b']);
      expect(module.input('${prefix}a').value, LogicValue.one);
    });
  }

  test('released waveform wrapper still captures VCD', () async {
    final directory =
        Directory.systemTemp.createTempSync('rohd_compatibility_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = Logic()..put(0);
    final mod = _CompatibilityModule(source);
    await mod.build();
    final outputPath = '${directory.path}/waves.vcd';

    final dumper = Dumper(mod, outputPath: outputPath);
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

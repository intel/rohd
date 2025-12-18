// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_builder_test.dart
// Unit tests for generation of the system verilog using synth builder.
//
// 2023 April 10
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/schematic.dart';
import 'package:test/test.dart';

class TopModule extends Module {
  TopModule(Logic a, Logic b) : super(name: 'topmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final y = addOutput('y', width: a.width);
    final z = addOutput('z', width: b.width);
    final z2 = addOutput('z2', width: b.width);

    y <= AModule(a).y;
    z <= BModule(b).zz;
    z2 <= BModule(b).zz;
  }
}

class AModule extends Module {
  Logic get y => output('y');

  AModule(Logic a) : super(name: 'amodule') {
    a = addInput('a', a, width: a.width);
    final y = addOutput('y', width: a.width);

    final tmp = Logic(width: a.width);
    y <= tmp;
    tmp <= a;
  }
}

class BModule extends Module {
  Logic get zz => output('zz');
  BModule(Logic bb) : super(name: 'bmodule') {
    bb = addInput('bb', bb, width: bb.width);
    final zz = addOutput('zz', width: bb.width);

    zz <= ~bb;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('synth builder', () {
    test('should throw exception if module is not built', () async {
      final mod = TopModule(Logic(width: 4), Logic());
      expect(() async {
        SynthBuilder(mod, SystemVerilogSynthesizer());
      }, throwsA((dynamic e) => e is ModuleNotBuiltException));
    });

    test('should able to create submodule in system verilog rtl', () async {
      final mod = TopModule(Logic(width: 4), Logic());
      await mod.build();

      for (final submod in mod.subModules) {
        final synth = SynthBuilder(submod, SystemVerilogSynthesizer());
        final firstSynthFileContents = synth.getSynthFileContents()[0];
        expect(
            firstSynthFileContents.contents, contains(submod.definitionName));
        expect(firstSynthFileContents.name, submod.definitionName);

        expect(
            synth.synthesisResults.first.toSynthFileContents().first.contents,
            firstSynthFileContents.contents);

        expect(firstSynthFileContents.description,
            contains(submod.definitionName));

        // test backwards compatibility
        expect(
            // ignore: deprecated_member_use_from_same_package
            synth.getFileContents().first,
            firstSynthFileContents.toString());
      }
    });

    test('multi-top synthbuilder works', () async {
      final top1 = TopModule(Logic(), Logic());
      final top2 = TopModule(Logic(width: 8), Logic());

      await top1.build();
      await top2.build();

      final synthBuilder =
          SynthBuilder.multi([top1, top2], SystemVerilogSynthesizer());
      final synthResults = synthBuilder.synthesisResults;

      expect(synthResults.where((e) => e.module == top1).length, 1);
      expect(synthResults.where((e) => e.module == top2).length, 1);
      expect(synthResults.where((e) => e.module is AModule).length, 2);
      expect(synthResults.where((e) => e.module is BModule).length, 1);
    });
  });

  group('schematic synthesizer', () {
    test('should throw exception if module is not built', () async {
      final mod = TopModule(Logic(width: 4), Logic());
      expect(() {
        SynthBuilder(mod, SchematicSynthesizer());
      }, throwsA((dynamic e) => e is ModuleNotBuiltException));
    });

    test('should generate schematic for simple module', () async {
      final mod = TopModule(Logic(width: 4), Logic());
      await mod.build();

      final synth = SynthBuilder(mod, SchematicSynthesizer());
      final results = synth.synthesisResults;

      // Should have results for TopModule, AModule, and BModule
      expect(results.isNotEmpty, isTrue);

      // Check that we can get file contents
      final files = synth.getSynthFileContents();
      expect(files.isNotEmpty, isTrue);

      // Each result should be a SchematicSynthesisResult
      for (final result in results) {
        expect(result, isA<SchematicSynthesisResult>());
        final schematicResult = result as SchematicSynthesisResult;
        expect(schematicResult.ports, isNotEmpty);
      }
    });

    test('schematic synthesizer generates JSON output', () async {
      final mod = AModule(Logic(width: 8));
      await mod.build();

      final synth = SynthBuilder(mod, SchematicSynthesizer());
      final files = synth.getSynthFileContents();

      expect(files.length, 1);
      expect(files.first.name, contains('AModule'));
      expect(files.first.name, endsWith('.rohd.json'));
      expect(files.first.contents, contains('"modules"'));
      expect(files.first.contents, contains('"ports"'));
    });

    test('schematic synthesizer handles module hierarchy', () async {
      final mod = TopModule(Logic(width: 4), Logic());
      await mod.build();

      final synth = SynthBuilder(mod, SchematicSynthesizer());
      final results = synth.synthesisResults;

      // Should have results for TopModule, AModule, and BModule
      final moduleTypes = results.map((r) => r.module.definitionName).toSet();
      expect(moduleTypes, contains('TopModule'));
    });

    test('schematic synthesizer deduplicates identical modules', () async {
      final mod = TopModule(Logic(width: 4), Logic());
      await mod.build();

      final synth = SynthBuilder(mod, SchematicSynthesizer());
      final results = synth.synthesisResults;

      // BModule is instantiated twice with same width, should be deduplicated
      final bModuleResults =
          results.where((r) => r.module.definitionName == 'BModule');
      expect(bModuleResults.length, 1);
    });

    test('multi-top schematic synthesizer works', () async {
      final top1 = TopModule(Logic(), Logic());
      final top2 = TopModule(Logic(width: 8), Logic());

      await top1.build();
      await top2.build();

      final synthBuilder =
          SynthBuilder.multi([top1, top2], SchematicSynthesizer());
      final synthResults = synthBuilder.synthesisResults;

      expect(synthResults.where((e) => e.module == top1).length, 1);
      expect(synthResults.where((e) => e.module == top2).length, 1);
    });
  });
}

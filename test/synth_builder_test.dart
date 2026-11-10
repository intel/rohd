// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_builder_test.dart
// Unit tests for generation of the system verilog using synth builder.
//
// 2023 April 10
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/simcompare.dart';
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

enum _InlineLookupState { idle, starting, busy, done }

class _InlineLookupModule extends Module {
  final int laneCount;

  _InlineLookupModule(Logic source, {required this.laneCount})
      : super(
            name: 'inline_lookup',
            definitionName: 'InlineLookup_L${laneCount}_W${source.width}'
                '_E${source is LogicEnum}') {
    source = addTypedInput('source', source);
    for (var index = 0; index < laneCount; index++) {
      addOutput('result_$index', width: source.width) <=
          ~((source ^ Const(index % 4, width: source.width)) &
              Const(1, width: source.width));
    }
  }
}

class _InlineLookupTop extends Module {
  final int laneCount;

  _InlineLookupTop(Logic source, {required this.laneCount})
      : super(
            name: 'inline_lookup_top',
            definitionName: 'InlineLookupTop_L${laneCount}_W${source.width}'
                '_E${source is LogicEnum}') {
    source = addTypedInput('source', source);
    final child = _InlineLookupModule(source, laneCount: laneCount);
    for (var index = 0; index < laneCount; index++) {
      addOutput('result_$index', width: source.width) <=
          child.output('result_$index');
    }
  }
}

class _InlineLookupNetHarness extends Module {
  _InlineLookupNetHarness() : super(name: 'inline_lookup_nets') {
    final a = addInOut('a', LogicNet(width: 2), width: 2);
    final b = addInOut('b', LogicNet(width: 2), width: 2);
    addInOut('forward', LogicNet(width: 4), width: 4) <= [a, b].concat();
    addInOut('reversed', LogicNet(width: 4), width: 4) <= [b, a].concat();
    addOutput('observed', width: 2) <= ~((a ^ b) & Const(1, width: 2));
  }
}

class _ConcatScalingModule extends Module {
  final int count;

  _ConcatScalingModule(Logic a, Logic b, {required this.count})
      : super(definitionName: 'ConcatScaling_C$count') {
    a = addInput('a', a, width: 2);
    b = addInput('b', b, width: 2);
    for (var index = 0; index < count; index++) {
      addOutput('result_$index', width: 4) <= [a, b].concat();
    }
  }
}

class _ConcatScalingTop extends Module {
  final int count;

  _ConcatScalingTop({required this.count})
      : super(definitionName: 'ConcatScalingTop_C$count') {
    final a = addInput('a', Logic(width: 2), width: 2);
    final b = addInput('b', Logic(width: 2), width: 2);
    final child = _ConcatScalingModule(a, b, count: count);
    for (var index = 0; index < count; index++) {
      addOutput('result_$index', width: 4) <= child.output('result_$index');
    }
  }
}

class _CountingSynthDefinition extends SystemVerilogSynthModuleDefinition {
  int submoduleVisits = 0;

  _CountingSynthDefinition(super.module);

  @override
  Iterable<SynthSubModuleInstantiation> get subModuleInstantiations sync* {
    for (final instantiation in super.subModuleInstantiations) {
      submoduleVisits++;
      yield instantiation;
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('synth builder', () {
    test('should throw exception if module is not built', () {
      final mod = TopModule(Logic(width: 4), Logic());
      expect(() {
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

    group('synthesis scaling', () {
      for (final laneCount in [8, 128]) {
        // A shared input has one alias per consumer, but only one snapshot.
        test('high-fanout alias snapshots are shared: lanes=$laneCount',
            () async {
          final dut = _InlineLookupTop(Logic(width: 2), laneCount: laneCount);
          await dut.build();
          final child = dut.subModules.whereType<_InlineLookupModule>().single;
          final definition = SystemVerilogSynthModuleDefinition(child);
          final source = definition.getSynthLogic(child.input('source'))!;
          final snapshots = Set<List<Logic>>.identity();
          for (var index = 0; index < laneCount; index++) {
            snapshots.add(source.logics);
          }
          expect(source.logics.length, greaterThanOrEqualTo(laneCount));
          expect(snapshots.length, 1);
        });
      }

      for (final count in [64, 256]) {
        // Count actual traversals rather than applying a wall-clock threshold.
        test('scalar concat driver checks stay linear: count=$count', () async {
          final dut = _ConcatScalingTop(count: count);
          await dut.build();
          final child = dut.subModules.whereType<_ConcatScalingModule>().single;
          final definition = _CountingSynthDefinition(child);
          expect(
              definition.moduleToSubModuleInstantiationMap, hasLength(count));
          expect(definition.submoduleVisits, lessThanOrEqualTo(64 * count),
              reason:
                  'Synthesis must not rescan all modules for every concat.');
        });
      }

      // Exhaust both two-bit inputs and observe every nested child output.
      test('scalar concat indexing preserves generated behavior', () async {
        final dut = _ConcatScalingTop(count: 4);
        await dut.build();
        final vectors = [
          for (var a = 0; a < 4; a++)
            for (var b = 0; b < 4; b++)
              Vector(
                {'a': a, 'b': b},
                {
                  for (var index = 0; index < 4; index++)
                    'result_$index': (a << 2) | b,
                },
              ),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, vectors);
      });
    });

    group('inline lookup maps', () {
      for (final enumPorts in [false, true]) {
        Logic source() =>
            enumPorts ? LogicEnum(_InlineLookupState.values) : Logic(width: 2);

        for (final generateEnums in [false, true]) {
          for (final laneCount in [8, 128]) {
            // Count distinct maps rather than relying on noisy heap samples.
            // Exercise multiple inline levels, including after enum lowering.
            test(
                'storage is bounded by mapped ports: lanes=$laneCount'
                ' enumPorts=$enumPorts generateEnums=$generateEnums', () async {
              final dut = _InlineLookupTop(source(), laneCount: laneCount);
              await dut.build();
              final child =
                  dut.subModules.whereType<_InlineLookupModule>().single;
              final definition = SystemVerilogSynthModuleDefinition(child,
                  generateEnums: generateEnums);
              final uniqueMaps = Set<
                  Map<SynthLogic,
                      SystemVerilogSynthSubModuleInstantiation>>.identity();
              var retainedEntries = 0;
              var mappedPorts = 0;
              for (final instantiation in definition.subModuleInstantiations
                  .cast<SystemVerilogSynthSubModuleInstantiation>()) {
                final map =
                    instantiation.synthLogicToInlineableSynthSubmoduleMap!;
                if (uniqueMaps.add(map)) {
                  retainedEntries += map.length;
                }
                mappedPorts += instantiation.inputMapping.length +
                    instantiation.outputMapping.length +
                    instantiation.inOutMapping.length;
              }

              expect(definition.inputs.single.isEnum, enumPorts);
              expect(retainedEntries, greaterThan(0),
                  reason: 'The fixture must exercise recursive inlining.');
              expect(retainedEntries, lessThanOrEqualTo(mappedPorts),
                  reason: 'Inline lookup storage must scale with port'
                      ' references, counting shared maps only once.');
              expect(uniqueMaps, hasLength(1),
                  reason: 'All instances must share one inline lookup table,'
                      ' including after enum-port lowering.');
              expect(() => uniqueMaps.single.clear(), throwsUnsupportedError);
            });
          }

          // Exhaust two-bit inputs through nested, three-operation lanes.
          test(
              'recursive expressions preserve values: enumPorts=$enumPorts'
              ' generateEnums=$generateEnums', () async {
            final dut = _InlineLookupTop(source(), laneCount: 4);
            await dut.build();
            final vectors = [
              for (var value = 0; value < 4; value++)
                Vector(
                  {'source': value},
                  {
                    for (var index = 0; index < 4; index++)
                      'result_$index': ~((value ^ index) & 1) & 3,
                  },
                ),
            ];
            await SimCompare.checkFunctionalVector(dut, vectors);
            SimCompare.checkIverilogVector(dut, vectors,
                synthesizerConfiguration: SystemVerilogSynthesizerConfiguration(
                    generateEnums: generateEnums));
          });
        }
      }

      // Separate bidirectional concats need private helper mappings while
      // sharing the inline producers used by the observed output.
      test('net-helper mappings stay isolated from the shared lookup',
          () async {
        final dut = _InlineLookupNetHarness();
        await dut.build();
        final definition = SystemVerilogSynthModuleDefinition(dut);
        final instantiations = definition.subModuleInstantiations
            .cast<SystemVerilogSynthSubModuleInstantiation>();
        final shared = instantiations
            .firstWhere(
                (instantiation) => instantiation.module is InlineSystemVerilog)
            .synthLogicToInlineableSynthSubmoduleMap!;
        expect(shared, isNotEmpty);
        final helpers = instantiations
            .where((instantiation) => !identical(
                instantiation.synthLogicToInlineableSynthSubmoduleMap, shared))
            .toList();
        expect(helpers.length, greaterThanOrEqualTo(2));
        for (final helper in helpers) {
          final map = helper.synthLogicToInlineableSynthSubmoduleMap!;
          final privateKeys =
              map.keys.where((key) => !shared.containsKey(key)).toList();
          expect(privateKeys, hasLength(1));
          for (final other
              in helpers.where((other) => !identical(other, helper))) {
            expect(other.synthLogicToInlineableSynthSubmoduleMap,
                isNot(contains(privateKeys.single)));
          }
          expect(map.clear, throwsUnsupportedError);
        }

        final vectors = [
          for (var a = 0; a < 4; a++)
            for (var b = 0; b < 4; b++)
              Vector({
                'a': a,
                'b': b
              }, {
                'forward': (a << 2) | b,
                'reversed': (b << 2) | a,
                'observed': ~((a ^ b) & 1) & 3,
              }),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, vectors);
      });
    });
  });
}

// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_name_config_test.dart
// Unit tests for logic naming using configuration for naming preferences.
//
// 2026 September 15
// Author: Max Korbel <max.korbel@intel.com>

// Legacy API calls are intentional coverage for deprecated generateSynth().
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import 'naming_test_utils.dart';

class FunctionGeneratedModule extends Module {
  FunctionGeneratedModule(
      void Function(Logic in1, Logic in2, Logic out1) builder) {
    builder(
      addInput('in1', Logic()),
      addInput('in2', Logic()),
      addOutput('out1'),
    );
  }
}

class _PreservedChain extends Module {
  final aliases = <Logic>[];
  final bridges = <Logic>[];

  _PreservedChain(List<Naming> namings, String placement,
      {Naming? bridgeNaming, bool reverseOutputs = false}) {
    var previous =
        addInput(placement == 'input' ? 'shared' : 'source', Logic());
    for (final naming in namings) {
      if (bridgeNaming != null && aliases.isNotEmpty) {
        final bridge =
            Logic(name: 'bridge${bridges.length}', naming: bridgeNaming)
              ..gets(previous);
        bridges.add(bridge);
        previous = bridge;
      }
      final alias = Logic(name: 'shared', naming: naming)..gets(previous);
      aliases.add(alias);
      previous = alias;
    }
    final outputs = [
      (placement == 'output' ? 'shared' : 'result', previous),
      ('early', aliases.first),
      ('middle', aliases[1]),
    ];
    for (final (name, signal) in reverseOutputs ? outputs.reversed : outputs) {
      addOutput(name) <= signal;
    }
  }
}

/// Exercises array merging and leaf mappings with packed output monitors.
///
/// Icarus does not propagate unpacked DUT outputs into the testbench's `logic`
/// arrays, so the monitors expose those values for its four-state checks.
class _PreservedArrayChain extends Module {
  final aliases = <LogicArray>[];

  _PreservedArrayChain(int unpackedDimensions) {
    var previous = addInputArray(
      'source',
      LogicArray([2, 2], 2, numUnpackedDimensions: unpackedDimensions),
      dimensions: [2, 2],
      elementWidth: 2,
      numUnpackedDimensions: unpackedDimensions,
    );
    for (final naming in [
      Naming.reserved,
      Naming.renameable,
      Naming.reserved
    ]) {
      final alias = LogicArray([2, 2], 2,
          name: 'shared',
          naming: naming,
          numUnpackedDimensions: unpackedDimensions)
        ..gets(previous);
      aliases.add(alias);
      previous = alias;
    }
    final shared = addOutputArray('shared',
        dimensions: [2, 2],
        elementWidth: 2,
        numUnpackedDimensions: unpackedDimensions);
    shared <= previous;
    addOutput('result', width: 8) <= shared.packed;
    addOutput('early', width: 8) <= aliases.first.packed;
  }
}

class _PreservedNetChain extends Module {
  final aliases = <LogicNet>[];

  _PreservedNetChain({required bool reversed}) {
    var previous = addInOut('shared', LogicNet());
    for (final naming in [
      Naming.reserved,
      Naming.renameable,
      Naming.reserved
    ]) {
      final alias = LogicNet(name: 'shared', naming: naming);
      if (reversed) {
        previous <= alias;
      } else {
        alias <= previous;
      }
      aliases.add(alias);
      previous = alias;
    }
    addOutput('result') <= previous;
    addOutput('early') <= aliases.first;
  }
}

void main() {
  tearDown(Simulator.reset);

  group('same-name preserved signals', () {
    for (final firstNaming in [Naming.reserved, Naming.renameable]) {
      for (final secondNaming in [Naming.reserved, Naming.renameable]) {
        for (final thirdNaming in [Naming.reserved, Naming.renameable]) {
          final namings = [firstNaming, secondNaming, thirdNaming];
          for (final placement in ['internal', 'input', 'output']) {
            test(
                '${namings.map((naming) => naming.name).join(', ')} '
                'chain at $placement', () async {
              final dut = _PreservedChain(namings, placement);
              await dut.build();
              final definition = SystemVerilogSynthModuleDefinition(dut);
              final shared = definition.getSynthLogic(dut.aliases.first)!;

              expect(shared.name, 'shared');
              expect(shared.mergeable, isFalse);
              expect(shared.isClearable, isFalse);
              expect(shared.hasPreservedName, isTrue);
              expect(shared.logics, containsAll(dut.aliases));
              expect(shared.isPort(dut), placement != 'internal');
              for (final alias in dut.aliases) {
                expect(definition.getSynthLogic(alias), same(shared));
                expect(dut.namer.signalNameOf(alias), 'shared');
              }

              final baseNames = collectSynthNames(SynthModuleDefinition(dut));
              final svNames = collectSynthNames(definition);
              for (final alias in dut.aliases) {
                expect(baseNames[alias], 'shared');
                expect(svNames[alias], baseNames[alias]);
              }

              String generateBody() =>
                  SynthBuilder(dut, SystemVerilogSynthesizer())
                      .getSynthFileContents()
                      .join();
              final sv = generateBody();
              expect(generateBody(), sv);
              expect(sv, isNot(contains('shared_')));
              expect('logic'.allMatches(sv).length,
                  placement == 'internal' ? 5 : 4);

              final vectors = [
                for (final value in [0, 1, 'x', 'z'])
                  Vector({
                    placement == 'input' ? 'shared' : 'source': value
                  }, {
                    placement == 'output' ? 'shared' : 'result': value,
                    'early': value,
                    'middle': value,
                  }),
              ];
              await SimCompare.checkFunctionalVector(dut, vectors);
              SimCompare.checkIverilogVector(dut, vectors);
            });
          }
        }
      }
    }

    for (final bridgeNaming in [Naming.mergeable, Naming.unnamed]) {
      for (final reverseOutputs in [false, true]) {
        test('${bridgeNaming.name} bridges, reverseOutputs=$reverseOutputs',
            () async {
          final dut = _PreservedChain(
              [Naming.reserved, Naming.renameable, Naming.reserved], 'internal',
              bridgeNaming: bridgeNaming, reverseOutputs: reverseOutputs);
          await dut.build();
          final definition = SystemVerilogSynthModuleDefinition(dut);
          final shared = definition.getSynthLogic(dut.aliases.first)!;
          final originals = [...dut.aliases, ...dut.bridges];
          expect(shared.name, 'shared');
          expect(shared.logics, containsAll(originals));
          expect(shared.isClearable, isFalse);
          for (final signal in originals) {
            expect(definition.getSynthLogic(signal), same(shared));
            expect(dut.namer.signalNameOf(signal), 'shared');
          }
          expect(dut.generateSynth(), isNot(contains('shared_')));
          expect(dut.generateSynth(), isNot(contains('bridge')));

          final vectors = [
            for (final value in [0, 1, 'x', 'z'])
              Vector({'source': value},
                  {'result': value, 'early': value, 'middle': value}),
          ];
          await SimCompare.checkFunctionalVector(dut, vectors);
          SimCompare.checkIverilogVector(dut, vectors);
        });
      }
    }

    for (final reversed in [false, true]) {
      test('same-name fanout, reversed=$reversed', () async {
        final signals = <Logic>[];
        final dut = FunctionGeneratedModule((in1, in2, out1) {
          final root = Logic(name: 'shared', naming: Naming.reserved)
            ..gets(in1);
          final first = Logic(name: 'shared')..gets(root);
          final second = Logic(name: 'shared', naming: Naming.reserved)
            ..gets(root);
          signals.addAll([root, first, second]);
          out1 <= (reversed ? second | first : first | second);
        });
        await dut.build();
        final definition = SystemVerilogSynthModuleDefinition(dut);
        final shared = definition.getSynthLogic(signals.first)!;
        expect(shared.name, 'shared');
        expect(shared.logics, containsAll(signals));
        for (final signal in signals) {
          expect(definition.getSynthLogic(signal), same(shared));
        }
        expect(dut.generateSynth(), isNot(contains('shared_')));
        final vectors = [
          Vector({'in1': 0}, {'out1': 0}),
          Vector({'in1': 1}, {'out1': 1}),
          Vector({'in1': 'x'}, {'out1': 'x'}),
          Vector({'in1': 'z'}, {'out1': 'x'}),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, vectors);
      });

      test('two merged groups retain all members, reversed=$reversed',
          () async {
        final dut = _PreservedChain([
          Naming.reserved,
          Naming.renameable,
          Naming.renameable,
          Naming.reserved,
        ], 'internal');
        await dut.build();
        final definition = SynthModuleDefinition(dut);
        final signals = [
          for (final alias in dut.aliases)
            SynthLogic(alias, parentSynthModuleDefinition: definition),
        ];
        final firstPair = SynthLogic.tryMerge(signals[0], signals[1])!;
        final secondPair = SynthLogic.tryMerge(signals[2], signals[3])!;
        expect(firstPair.kept.logics, hasLength(2));
        expect(secondPair.kept.logics, hasLength(2));
        final merged = reversed
            ? SynthLogic.tryMerge(secondPair.kept, firstPair.kept)!
            : SynthLogic.tryMerge(firstPair.kept, secondPair.kept)!;
        expect(merged.kept.logics, unorderedEquals(dut.aliases));
        expect(merged.kept.isReserved, isTrue);
        expect(merged.kept.isClearable, isFalse);
        for (final signal in signals) {
          expect(signal.resolved, same(merged.kept));
        }
      });
    }

    for (final naming in [Naming.reserved, Naming.renameable]) {
      test('${naming.name} different names remain declared', () async {
        final dut = FunctionGeneratedModule((in1, in2, out1) {
          final first = Logic(name: 'first', naming: naming)..gets(in1);
          final second = Logic(name: 'second', naming: naming)..gets(first);
          out1 <= second;
        });
        await dut.build();
        final sv = dut.generateSynth();
        expect(sv, contains('assign second = first;'));
        expect('logic'.allMatches(sv).length, 5);
      });

      test('${naming.name} same-name constant aliases remain named', () async {
        final aliases = <Logic>[];
        final dut = FunctionGeneratedModule((in1, in2, out1) {
          final first = Logic(name: 'shared', naming: naming)..gets(Const(1));
          final second = Logic(name: 'shared', naming: naming)..gets(first);
          aliases.addAll([first, second]);
          out1 <= second;
        });
        await dut.build();
        final names = collectSynthNames(SynthModuleDefinition(dut));
        expect(aliases.map((alias) => names[alias]), everyElement('shared'));
        expect(dut.generateSynth(), contains("assign shared = 1'h1;"));
      });

      test('${naming.name} unrelated same-name port is still a collision',
          () async {
        final dut = FunctionGeneratedModule((in1, in2, out1) {
          final alias = Logic(name: 'in1', naming: naming)..gets(in2);
          out1 <= alias;
        });
        await dut.build();
        if (naming == Naming.reserved) {
          expect(dut.generateSynth,
              throwsA(isA<UnavailableReservedNameException>()));
        } else {
          expect(dut.generateSynth(), contains('assign in1_0 = in2;'));
        }
      });
    }

    test('unrelated renameable groups are uniquified as groups', () async {
      final aliases = <Logic>[];
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        for (final source in [in1, in2]) {
          final first = Logic(name: 'shared')..gets(source);
          final second = Logic(name: 'shared')..gets(first);
          aliases.addAll([first, second]);
        }
        out1 <= aliases[1] | aliases[3];
      });
      await dut.build();
      final names = collectSynthNames(SynthModuleDefinition(dut));
      expect(names[aliases[0]], names[aliases[1]]);
      expect(names[aliases[2]], names[aliases[3]]);
      expect({names[aliases[0]], names[aliases[2]]}, {'shared', 'shared_0'});
      final vectors = [
        Vector({'in1': 0, 'in2': 1}, {'out1': 1}),
        Vector({'in1': 1, 'in2': 0}, {'out1': 1}),
        Vector({'in1': 0, 'in2': 0}, {'out1': 0}),
      ];
      await SimCompare.checkFunctionalVector(dut, vectors);
      SimCompare.checkIverilogVector(dut, vectors);
    });

    test('equal structure leaf names keep distinct qualified names', () async {
      final leaves = <Logic>[];
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final first = Logic(name: 'shared')..gets(in1);
        final second = Logic(name: 'shared')..gets(first);
        LogicStructure([first], name: 'left');
        LogicStructure([second], name: 'right');
        leaves.addAll([first, second]);
        out1 <= second;
      });
      await dut.build();
      final names = collectSynthNames(SynthModuleDefinition(dut));
      expect(names[leaves[0]], 'left_shared');
      expect(names[leaves[1]], 'right_shared');
    });

    for (final unpackedDimensions in [0, 1, 2]) {
      test('whole array chain with $unpackedDimensions unpacked dimensions',
          () async {
        final dut = _PreservedArrayChain(unpackedDimensions);
        await dut.build();
        final definition = SystemVerilogSynthModuleDefinition(dut);
        final port = dut.output('shared') as LogicArray;
        final shared = definition.getSynthLogic(port)!;
        expect(shared.name, 'shared');
        expect(shared.isPort(dut), isTrue);
        for (final alias in dut.aliases) {
          expect(definition.getSynthLogic(alias), same(shared));
          for (var index = 0; index < alias.leafElements.length; index++) {
            expect(definition.getSynthLogic(alias.leafElements[index]),
                same(definition.getSynthLogic(port.leafElements[index])));
          }
        }
        expect(dut.generateSynth(), isNot(contains('shared_')));
        final vectors = [
          for (final value in [0, 0xa5, 0x5a, '10xz01zx'])
            Vector({'source': value},
                {'shared': value, 'result': value, 'early': value}),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, [
          for (final vector in vectors)
            Vector(vector.inputValues, {
              if (unpackedDimensions == 0)
                'shared': vector.expectedOutputValues['shared'],
              'result': vector.expectedOutputValues['result'],
              'early': vector.expectedOutputValues['early'],
            }),
        ]);
      });
    }

    for (final reversed in [false, true]) {
      test('net chain merges with reversed=$reversed', () async {
        final dut = _PreservedNetChain(reversed: reversed);
        await dut.build();
        final definition = SystemVerilogSynthModuleDefinition(dut);
        final shared = definition.getSynthLogic(dut.inOut('shared'))!;
        expect(shared.isNet, isTrue);
        expect(shared.isPort(dut), isTrue);
        expect(shared.logics, containsAll(dut.aliases));
        for (final alias in dut.aliases) {
          expect(definition.getSynthLogic(alias), same(shared));
        }
        expect(dut.generateSynth(), isNot(contains('net_connect')));
        final vectors = [
          for (final value in [0, 1, 'x', 'z'])
            Vector({'shared': value}, {'result': value, 'early': value}),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, vectors);
      });
    }

    test('same names do not bypass structural merge restrictions', () async {
      final firstArray = LogicArray([2], 2, name: 'shared');
      final secondArray = LogicArray([2], 2, name: 'shared');
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        firstArray <= in1.replicate(4);
        secondArray <= in2.replicate(4);
        out1 <= firstArray.elements.first[0] | secondArray.elements.first[0];
      });
      await dut.build();
      final definition = SynthModuleDefinition(dut);
      SynthLogic synth(Logic logic) =>
          SynthLogic(logic, parentSynthModuleDefinition: definition);
      final scalar = synth(Logic(name: 'shared', width: 4));
      final array = synth(LogicArray([2], 2, name: 'shared'));
      final incompatible = [
        synth(LogicNet(name: 'shared', width: 4)),
        synth(Logic(name: 'shared', width: 3)),
        array,
        synth(Const(0, width: 4)),
      ];
      for (final other in incompatible) {
        expect(SynthLogic.tryMerge(scalar, other), isNull);
        expect(SynthLogic.tryMerge(other, scalar), isNull);
      }
      for (final other in [
        synth(LogicArray([4], 1, name: 'shared')),
        synth(LogicArray([2], 2, name: 'shared', numUnpackedDimensions: 1)),
      ]) {
        expect(SynthLogic.tryMerge(array, other), isNull);
        expect(SynthLogic.tryMerge(other, array), isNull);
      }

      final firstElement = definition.getSynthLogic(firstArray.elements.first)!;
      final secondElement =
          definition.getSynthLogic(secondArray.elements.first)!;
      expect(SynthLogic.tryMerge(firstElement, secondElement), isNull);
    });
  });

  test('renameable name stays present', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(name: 'intermediate');
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    expect(sv, contains('intermediate'));
  });

  test('mergeable name is omitted', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(
        name: 'intermediate',
        naming: Naming.mergeable,
      );
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // no intermediate
    expect(sv.contains('intermediate'), isFalse);
  });

  test('unnamed is omitted', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic();
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // just the ports
    expect('logic'.allMatches(sv).length, 3);
  });

  test('unnamed is omitted even when named', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(name: 'badname', naming: Naming.unnamed);
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // just the ports
    expect('logic'.allMatches(sv).length, 3);
  });

  test('reserved name stays present', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate =
          Logic(name: 'intermediate_1', naming: Naming.reserved);
      intermediate <= in1;

      for (var i = 0; i < 6; i++) {
        Logic(name: 'intermediate') <= in2;
      }

      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // held one sticks
    expect(sv, contains('intermediate_1 = in1'));

    // renaming works, skips over reserved
    expect(sv, contains('intermediate_2 = in2'));
  });

  for (final naming in [Naming.reserved, Naming.renameable]) {
    test('${naming.name} and input with same name merge', () async {
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final intermediate = Logic(name: 'in1', naming: naming);
        intermediate <= in1;

        out1 <= intermediate;
      });
      await dut.build();
      final sv = dut.generateSynth();

      expect('logic'.allMatches(sv).length, 3);
      expect(sv, contains('assign out1 = in1;'));
    });

    test('${naming.name} and output with same name merge', () async {
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final intermediate = Logic(name: 'out1', naming: naming);
        intermediate <= in1;

        out1 <= intermediate;
      });
      await dut.build();
      final sv = dut.generateSynth();

      expect('logic'.allMatches(sv).length, 3);
      expect(sv, contains('assign out1 = in1;'));
    });
  }

  test('2x reserved name errors', () async {
    try {
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final intermediate =
            Logic(name: 'intermediate', naming: Naming.reserved);
        intermediate <= in1;

        final intermediate2 =
            Logic(name: 'intermediate', naming: Naming.reserved);
        intermediate2 <= in2;

        out1 <= intermediate | intermediate2;
      });
      await dut.build();
      dut.generateSynth();
      fail('expected an exception!');
    } on Exception catch (e) {
      expect(e, isA<UnavailableReservedNameException>());
    }
  });

  test('unpreferred signals get lower priority when merging', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediatePre = Logic(
          name: Naming.unpreferredName('badname_pre'),
          naming: Naming.mergeable);
      final intermediate = Logic(name: 'goodname', naming: Naming.mergeable);
      final intermediatePost = Logic(
          name: Naming.unpreferredName('badname_post'),
          naming: Naming.mergeable);
      intermediatePre <= flop(in2, ~in1);
      intermediate <= intermediatePre;
      intermediatePost <= intermediate;
      out1 <= ~intermediatePost;
    });
    await dut.build();
    final sv = dut.generateSynth();

    expect(sv, contains('goodname'));
  });

  test('priority amongst different types of signals', () async {
    List<Logic> priorityList() => [
          Logic(name: 'unnamed', naming: Naming.unnamed),
          Logic(name: 'mergeable', naming: Naming.mergeable),
          Logic(
              name: Naming.unpreferredName('unpreferredRenameable'),
              naming: Naming.renameable),
          Logic(name: 'renameable', naming: Naming.renameable),
          Logic(name: 'reserved', naming: Naming.reserved),
        ];

    List<List<int>> allPermutations(List<int> initial) {
      final perms = <List<int>>[];
      for (var i = 0; i < initial.length; i++) {
        final first = initial[i];
        final remaining =
            initial.whereNotIndexed((index, element) => index == i).toList();
        final subPerms = allPermutations(remaining);
        for (final p in subPerms) {
          perms.add([first, ...p]);
        }
        perms.add([first]);
      }
      return perms;
    }

    final indexPermutations =
        allPermutations(List.generate(priorityList().length, (index) => index));

    for (final indexPermutation in indexPermutations) {
      var l = priorityList();

      final expectedName = l
          .lastWhereIndexedOrNull(
              (index, element) => indexPermutation.contains(index))!
          .name;

      l = indexPermutation.map((i) => l[i]).toList();

      final dut = FunctionGeneratedModule((in1, in2, out1) {
        var prev = flop(in2, ~in1);
        for (final s in l) {
          s <= prev;
          prev = s;
        }
        out1 <= ~prev;
      });
      await dut.build();
      final sv = dut.generateSynth();

      expect(sv, contains(expectedName),
          reason: 'Amongst ${l.map((e) => e.name).toList()},'
              ' should have had present $expectedName');
    }
  });

  test('non-mergeable name sticks around when not needed', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(name: 'intermediate');
      out1 <= in1 | in2;
      intermediate <= in1;
    });
    await dut.build();
    final sv = dut.generateSynth();

    expect(sv, contains('intermediate'));
  });
}

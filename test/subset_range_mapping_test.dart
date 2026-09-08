// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// subset_range_mapping_test.dart
// Tests for packed subset range mapping and isolated-bit preservation
//
// 2026 September 8
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class Producer extends Module {
  Producer(Logic seed) : super(name: 'producer') {
    seed = addInput('seed', seed, width: seed.width);
    addOutput('data_out', width: seed.width) <= seed;
  }
}

class Consumer extends Module with SystemVerilog {
  final bool expressionless;

  Consumer(int width, {Logic? data, this.expressionless = false})
      : super(name: 'consumer') {
    final dataIn =
        addInput('data_in', data ?? Logic(width: width), width: width);
    addOutput('observed', width: width) <= dataIn;
  }

  @override
  List<String> get expressionlessInputs => expressionless ? ['data_in'] : [];

  @override
  String? definitionVerilog(String definitionType) => null;
}

class ProducerHierarchy extends Module {
  ProducerHierarchy(Logic seed) : super(name: 'producer_hierarchy') {
    seed = addInput('seed', seed, width: seed.width);
    addOutput('data_out', width: seed.width) <=
        Producer(seed).output('data_out');
  }
}

class ConsumerHierarchy extends Module {
  ConsumerHierarchy(int width) : super(name: 'consumer_hierarchy') {
    final data = addInput('data_in', Logic(width: width), width: width);
    addOutput('observed', width: width) <=
        Consumer(width, data: data).output('observed');
  }
}

class ArrayConsumer extends Module {
  ArrayConsumer(int width) : super(name: 'array_consumer') {
    final data =
        addInputArray('data_in', LogicArray([width], 1), dimensions: [width]);
    addOutput('observed', width: width) <= data;
  }
}

class Record extends LogicStructure {
  Record({super.name = 'record'})
      : super(List.generate(4, (index) => Logic(name: 'bit$index')));

  @override
  Record clone({String? name}) => Record(name: name ?? this.name);
}

class StructureConsumer extends Module {
  StructureConsumer() : super(name: 'structure_consumer') {
    final data = addTypedInput('data_in', Record());
    addOutput('observed', width: 4) <= data;
  }
}

enum SourceKind { input, sibling, computed, nested, named, hierarchy }

enum DestinationKind { packed, array, structure, hierarchy }

class Top extends Module {
  Top({
    required bool useRange,
    int sourceWidth = 64,
    int lower = 40,
    int width = 2,
    SourceKind sourceKind = SourceKind.sibling,
    DestinationKind destinationKind = DestinationKind.packed,
    bool reverseAssignments = false,
    List<int>? sourceIndices,
  }) : super(name: 'top') {
    final seed =
        addInput('seed', Logic(width: sourceWidth), width: sourceWidth);
    final dataOut = switch (sourceKind) {
      SourceKind.input => seed,
      SourceKind.sibling => Producer(seed).output('data_out'),
      SourceKind.computed =>
        (~seed).named('computed', naming: Naming.mergeable),
      SourceKind.nested => seed.getRange(4, sourceWidth - 4),
      SourceKind.named => seed.named('source_stage', naming: Naming.renameable),
      SourceKind.hierarchy => ProducerHierarchy(seed).output('data_out'),
    };
    final consumer = switch (destinationKind) {
      DestinationKind.packed => Consumer(width),
      DestinationKind.array => ArrayConsumer(width),
      DestinationKind.structure => StructureConsumer(),
      DestinationKind.hierarchy => ConsumerHierarchy(width),
    };
    final dataIn = consumer.inputSource('data_in');
    if (useRange) {
      dataIn <=
          (sourceIndices == null
              ? dataOut.getRange(lower, lower + width)
              : [for (final index in sourceIndices) dataOut[index]].rswizzle());
    } else {
      final indices = List.generate(width, (index) => index);
      for (final index in reverseAssignments ? indices.reversed : indices) {
        dataIn.assignSubset([dataOut[sourceIndices?[index] ?? lower + index]],
            start: index);
      }
    }
    addOutput('observed', width: width) <= consumer.output('observed');
  }
}

class MixedTop extends Module {
  MixedTop({
    required bool useRange,
    required SourceKind sourceKind,
    required String tie,
    required bool fanout,
    bool isolatedBit = false,
  }) : super(name: 'mixed_top') {
    final seed = addInput('seed', Logic(width: 16), width: 16);
    final other = addInput('other', Logic(width: 16), width: 16);
    final source = sourceKind == SourceKind.computed
        ? (~seed).named('computed', naming: Naming.mergeable)
        : Producer(seed).output('data_out');
    final selectedWidth = isolatedBit ? 1 : 2;
    final consumer = Consumer(10 + selectedWidth);
    final dataIn = consumer.inputSource('data_in');
    if (useRange) {
      dataIn <=
          [
            source.getRange(2, 6),
            Const(LogicValue.ofString(tie)),
            source.getRange(12, 12 + selectedWidth),
            other.getRange(8, 10),
            source.getRange(3, 5),
          ].rswizzle();
    } else {
      for (final index in [3, 0, 2, 1]) {
        dataIn.assignSubset([source[index + 2]], start: index);
      }
      dataIn
        ..assignSubset(Const(LogicValue.ofString(tie)).elements, start: 4)
        ..assignSubset(
          [
            for (var index = 0; index < selectedWidth; index++)
              source[12 + index]
          ],
          start: 6,
        )
        ..assignSubset([other[8], other[9]], start: 6 + selectedWidth)
        ..assignSubset([source[3], source[4]], start: 8 + selectedWidth);
    }
    addOutput('observed', width: 10 + selectedWidth) <=
        consumer.output('observed');
    if (fanout) {
      addOutput('fanout', width: 16) <= source;
    }
  }
}

enum Guard { fanout, renameable, reserved, expressionless, partial, output }

class SplitRangeDefinition extends SystemVerilogSynthModuleDefinition {
  SplitRangeDefinition(super.module);

  @override
  void process() {
    final splitAssignments = [
      for (final assignment in assignments)
        if (assignment is RangeSynthAssignment)
          for (var index = 0; index < assignment.width; index++)
            RangeSynthAssignment(
              assignment.src,
              assignment.dst,
              srcUpperIndex: assignment.srcLowerIndex + index,
              srcLowerIndex: assignment.srcLowerIndex + index,
              dstUpperIndex: assignment.dstLowerIndex + index,
              dstLowerIndex: assignment.dstLowerIndex + index,
            )
        else
          assignment,
    ];
    assignments
      ..clear()
      ..addAll(splitAssignments);
    super.process();
  }
}

class GuardedTop extends Module {
  GuardedTop(
      {required Guard guard, required bool computed, bool isolatedBit = false})
      : super(name: 'guarded_top') {
    final seed = addInput('seed', Logic(width: 16), width: 16);
    final source = computed ? ~seed : Producer(seed).output('data_out');
    final width = guard == Guard.partial ? 6 : 4;
    final destination = Logic(
      width: width,
      name: 'destination',
      naming: switch (guard) {
        Guard.renameable => Naming.renameable,
        Guard.reserved => Naming.reserved,
        _ => Naming.mergeable,
      },
    );
    if (guard == Guard.partial) {
      destination
        ..assignSubset(
            [source[isolatedBit ? 0 : 3], source[isolatedBit ? 5 : 4]])
        ..assignSubset(
            [source[isolatedBit ? 6 : 11], source[isolatedBit ? 15 : 12]],
            start: 4);
    } else {
      final sourceIndices = isolatedBit ? [0, 5, 6, 15] : [3, 4, 5, 6];
      for (final index in [3, 0, 2, 1]) {
        destination.assignSubset([source[sourceIndices[index]]], start: index);
      }
    }
    final consumer = Consumer(
      width,
      data: destination,
      expressionless: guard == Guard.expressionless,
    );
    addOutput('observed', width: width) <= consumer.output('observed');
    if (guard == Guard.fanout) {
      final second = Consumer(width, data: destination);
      addOutput('second', width: width) <= second.output('observed');
    }
    if (guard == Guard.output) {
      addOutput('exposed', width: width) <= destination;
    }
  }
}

String _topBody(Module module) {
  final sv = module.generateSynth();
  final matches = RegExp(r'(?:^|\n)module ').allMatches(sv);
  return sv.substring(matches.last.start);
}

List<LogicValue> _patterns(int width) => [
      LogicValue.filled(width, LogicValue.zero),
      LogicValue.filled(width, LogicValue.one),
      for (final bit in {0, width ~/ 2, width - 1})
        LogicValue.ofBigInt(BigInt.one << bit, width),
      LogicValue.ofString(('10010110' * width).substring(0, width)),
      LogicValue.ofString(('10xz' * width).substring(0, width)),
      LogicValue.filled(width, LogicValue.x),
      LogicValue.filled(width, LogicValue.z),
    ];

void main() {
  tearDown(Simulator.reset);

  test('full-width four-state sibling mapping matches both representations',
      () async {
    final vectors = [
      for (final background in ['0', '1'])
        for (final upper in ['0', '1', 'x', 'z'])
          for (final lower in ['0', '1', 'x', 'z'])
            Vector({
              'seed': LogicValue.ofString(
                '${background * 22}$upper$lower${background * 40}',
              ),
            }, {
              'observed': LogicValue.ofString('$upper$lower'),
            }),
    ];

    for (final useRange in [false, true]) {
      final module = Top(useRange: useRange);
      await module.build();
      final body = _topBody(module);
      expect(
          body,
          contains(RegExp(
            r'\.data_in\(\(\{?\s*data_out\[41:40\]\s*\}?\)\)',
          )));
      expect(body, isNot(contains('_subset')));
      expect(body, isNot(contains('logic [1:0] data_in;')));
      expect(body, isNot(contains(RegExp(r'\bassign\b'))));
      expect(_topBody(module), body);
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);
      await Simulator.reset();
    }
  });

  for (final sourceKind in SourceKind.values) {
    final selectedSourceWidth = sourceKind == SourceKind.nested ? 88 : 96;
    for (final selection in [
      (lower: 0, width: 1),
      (lower: selectedSourceWidth - 1, width: 1),
      (lower: 0, width: 2),
      (lower: selectedSourceWidth - 2, width: 2),
      (lower: 37, width: 9),
      (lower: 17, width: 65),
      (lower: 0, width: selectedSourceWidth),
    ]) {
      test('boundary matrix ${sourceKind.name} $selection', () async {
        const sourceWidth = 96;
        final vectors = [
          for (final seed in _patterns(sourceWidth))
            Vector({
              'seed': seed
            }, {
              'observed': (switch (sourceKind) {
                SourceKind.computed => ~seed,
                SourceKind.nested => seed.getRange(4, sourceWidth - 4),
                _ => seed,
              })
                  .getRange(selection.lower, selection.lower + selection.width),
            }),
        ];
        for (final useRange in [false, true]) {
          final module = Top(
            useRange: useRange,
            sourceWidth: sourceWidth,
            lower: selection.lower,
            width: selection.width,
            sourceKind: sourceKind,
            reverseAssignments: true,
          );
          await module.build();
          final body = _topBody(module);
          expect(body, isNot(contains('data_in_subset')));
          if (selection.width != selectedSourceWidth) {
            expect(body, isNot(contains(RegExp(r'assign\s+data_in'))));
            expect(body, isNot(contains(RegExp(r'logic[^;]*\bdata_in;'))));
            expect(body, contains('.data_in(('));
          } else {
            expect(body, isNot(contains('.data_in()')));
          }
          expect(_topBody(module), body);
          await SimCompare.checkFunctionalVector(module, vectors);
          SimCompare.checkIverilogVector(module, vectors);
          await Simulator.reset();
        }
      });
    }
  }

  for (final sourceKind in SourceKind.values) {
    for (final sourceIndices in [
      [15, 4, 5, 0],
      [2, 3, 15, 8, 0, 10, 11],
      [4, 5, 4, 0, 15, 5],
    ]) {
      for (final reverseAssignments in [false, true]) {
        test(
            'isolated positions ${sourceKind.name} $sourceIndices '
            'reverse=$reverseAssignments', () async {
          const sourceWidth = 24;
          final vectors = [
            for (final seed in {
              ..._patterns(sourceWidth),
              for (final index in sourceIndices)
                LogicValue.ofBigInt(
                    BigInt.one <<
                        (index + (sourceKind == SourceKind.nested ? 4 : 0)),
                    sourceWidth),
            })
              Vector({
                'seed': seed
              }, {
                'observed': [
                  for (final index in sourceIndices)
                    (switch (sourceKind) {
                      SourceKind.computed => ~seed,
                      SourceKind.nested => seed.getRange(4, sourceWidth - 4),
                      _ => seed,
                    })[index],
                ].rswizzle(),
              }),
          ];
          for (final useRange in [false, true]) {
            final module = Top(
              useRange: useRange,
              sourceWidth: sourceWidth,
              width: sourceIndices.length,
              sourceKind: sourceKind,
              sourceIndices: sourceIndices,
              reverseAssignments: reverseAssignments,
            );
            await module.build();
            final body = _topBody(module);
            expect(body, isNot(contains('data_in_subset')));
            expect(body, isNot(contains(RegExp(r'assign\s+data_in'))));
            expect(body, isNot(contains(RegExp(r'logic[^;]*\bdata_in;'))));
            expect(body, contains('.data_in(('));
            expect(_topBody(module), body);
            await SimCompare.checkFunctionalVector(module, vectors);
            SimCompare.checkIverilogVector(module, vectors);
            await Simulator.reset();
          }
        });
      }
    }
  }

  for (final sourceKind in [SourceKind.sibling, SourceKind.computed]) {
    for (final fanout in [false, true]) {
      for (final tie in ['01', 'xx', 'zz']) {
        for (final isolatedBit in [false, true]) {
          test(
              'mixed ranges ${sourceKind.name} fanout=$fanout tie=$tie '
              'isolatedBit=$isolatedBit', () async {
            final vectors = [
              for (final seed in _patterns(16))
                Vector({
                  'seed': seed,
                  'other': ~seed
                }, {
                  'observed': [
                    (sourceKind == SourceKind.computed ? ~seed : seed)
                        .getRange(2, 6),
                    LogicValue.ofString(tie),
                    (sourceKind == SourceKind.computed ? ~seed : seed)
                        .getRange(12, isolatedBit ? 13 : 14),
                    (~seed).getRange(8, 10),
                    (sourceKind == SourceKind.computed ? ~seed : seed)
                        .getRange(3, 5),
                  ].rswizzle(),
                  if (fanout)
                    'fanout': sourceKind == SourceKind.computed ? ~seed : seed,
                }),
            ];
            for (final useRange in [false, true]) {
              final module = MixedTop(
                useRange: useRange,
                sourceKind: sourceKind,
                fanout: fanout,
                tie: tie,
                isolatedBit: isolatedBit,
              );
              await module.build();
              final body = _topBody(module);
              if (tie != 'zz') {
                expect(body, contains('.data_in(({'));
                expect(body, isNot(contains('data_in_subset')));
                expect(body, isNot(contains(RegExp(r'assign\s+data_in'))));
                expect(body, isNot(contains(RegExp(r'logic[^;]*\bdata_in;'))));
              }
              expect(_topBody(module), body);
              await SimCompare.checkFunctionalVector(module, vectors);
              SimCompare.checkIverilogVector(module, vectors);
              await Simulator.reset();
            }
          });
        }
      }
    }
  }

  for (final guard in Guard.values) {
    for (final computed in [false, true]) {
      for (final isolatedBit in [false, true]) {
        test('guard ${guard.name} computed=$computed isolatedBit=$isolatedBit',
            () async {
          final module = GuardedTop(
              guard: guard, computed: computed, isolatedBit: isolatedBit);
          await module.build();
          final body = _topBody(module);
          expect(body, contains(RegExp(r'\.data_in\([A-Za-z_]\w*\)')));
          expect(body, isNot(contains('.data_in((')));
          expect(body, contains(RegExp(r'\bassign\b')));
          final sourceIndices = isolatedBit ? [0, 5, 6, 15] : [3, 4, 5, 6];
          LogicValue selectedValue(LogicValue seed) => [
                for (final index in sourceIndices)
                  (computed ? ~seed : seed)[index],
              ].rswizzle();
          final vectors = [
            for (final seed in _patterns(16))
              Vector({
                'seed': seed
              }, {
                'observed': guard == Guard.partial
                    ? [
                        if (isolatedBit)
                          selectedValue(seed).getRange(0, 2)
                        else
                          (computed ? ~seed : seed).getRange(3, 5),
                        LogicValue.ofString('zz'),
                        if (isolatedBit)
                          selectedValue(seed).getRange(2, 4)
                        else
                          (computed ? ~seed : seed).getRange(11, 13),
                      ].rswizzle()
                    : selectedValue(seed),
                if (guard == Guard.fanout) 'second': selectedValue(seed),
                if (guard == Guard.output) 'exposed': selectedValue(seed),
              }),
          ];
          expect(_topBody(module), body);
          await SimCompare.checkFunctionalVector(module, vectors);
          SimCompare.checkIverilogVector(module, vectors);
        });
      }
    }
  }

  for (final destination in DestinationKind.values) {
    for (final sourceKind in [
      SourceKind.input,
      SourceKind.sibling,
      SourceKind.computed,
      SourceKind.hierarchy,
    ]) {
      test('topology ${sourceKind.name} to ${destination.name}', () async {
        final vectors = [
          for (final seed in _patterns(16))
            Vector({
              'seed': seed
            }, {
              'observed': (sourceKind == SourceKind.computed ? ~seed : seed)
                  .getRange(6, 10),
            }),
        ];
        for (final useRange in [false, true]) {
          final module = Top(
            useRange: useRange,
            sourceWidth: 16,
            lower: 6,
            width: 4,
            sourceKind: sourceKind,
            destinationKind: destination,
            reverseAssignments: true,
          );
          await module.build();
          final body = _topBody(module);
          expect(body, isNot(contains('.data_in()')));
          if (destination == DestinationKind.packed ||
              destination == DestinationKind.hierarchy) {
            expect(body, contains('.data_in(('));
            expect(body, isNot(contains('data_in_subset')));
            expect(body, isNot(contains(RegExp(r'assign\s+data_in'))));
            expect(body, isNot(contains(RegExp(r'logic[^;]*\bdata_in;'))));
          }
          expect(_topBody(module), body);
          await SimCompare.checkFunctionalVector(module, vectors);
          SimCompare.checkIverilogVector(module, vectors);
          await Simulator.reset();
        }
      });
    }
  }

  test('one-bit range assignments inline in the correct order', () async {
    final module = Top(useRange: false);
    await module.build();
    final definition = SplitRangeDefinition(module);
    final consumer = definition.subModuleInstantiations.singleWhere(
      (instantiation) => instantiation.module is Consumer,
    ) as SystemVerilogSynthSubModuleInstantiation;
    final sv = consumer.instantiationVerilog('Consumer')!;
    expect(sv, contains('.data_in((data_out[41:40]))'));
    expect(definition.assignments, isEmpty);
    expect(
        definition.internalSignals.any(
          (signal) => signal.needsDeclaration && signal.name == 'data_in',
        ),
        isFalse);
  });

  test('packed range reference follows replacement chains without ownership',
      () async {
    final module = Producer(Logic(width: 16));
    await module.build();
    final definition = SynthModuleDefinition(module);
    final base = SynthLogic(
      Logic(width: 16, name: 'base'),
      parentSynthModuleDefinition: definition,
    )..pickName();
    final reference = SynthLogicPackedRangeReference(
      base,
      3,
      11,
      parentSynthModuleDefinition: definition,
    );
    expect(reference.width, 9);
    expect(reference.name, '${base.name}[11:3]');
    expect(reference.needsDeclaration, isFalse);
    expect(reference.mergeable, isFalse);
    expect(reference.isPort(module), isFalse);

    final intermediate = SynthLogic(
      Logic(width: 16),
      parentSynthModuleDefinition: definition,
    );
    final replacement = definition.getSynthLogic(module.input('seed'))!;
    base.replacement = intermediate;
    intermediate.replacement = replacement;
    expect(reference.name, '${replacement.name}[11:3]');
    expect(reference.isPort(module), isTrue);
    expect(reference.hasSrcConnectionsPresent(),
        replacement.hasSrcConnectionsPresent());
    expect(reference.hasDstConnectionsPresent(),
        replacement.hasDstConnectionsPresent());
    reference.clearDeclaration();
    expect(replacement.declarationCleared, isFalse);
    expect(reference.name, '${replacement.name}[11:3]');
  });

  test('packed range reference rejects invalid bounds and unsupported bases',
      () async {
    final module = Producer(Logic(width: 16));
    await module.build();
    final definition = SynthModuleDefinition(module);
    final base = definition.getSynthLogic(module.input('seed'))!;
    for (final bounds in [
      (lower: -1, upper: 1),
      (lower: 3, upper: 2),
      (lower: 0, upper: 16)
    ]) {
      expect(
        () => SynthLogicPackedRangeReference(
          base,
          bounds.lower,
          bounds.upper,
          parentSynthModuleDefinition: definition,
        ),
        throwsA(isA<AssertionError>()),
      );
    }
    for (final unsupported in [
      LogicArray([16], 1),
      LogicNet(width: 16),
      Const(0, width: 16),
    ]) {
      expect(
        () => SynthLogicPackedRangeReference(
          SynthLogic(unsupported, parentSynthModuleDefinition: definition),
          2,
          3,
          parentSynthModuleDefinition: definition,
        ),
        throwsA(isA<AssertionError>()),
      );
    }
  });

  test('isolated source bit survives beside collapsed ranges', () async {
    final module = MixedTop(
      useRange: false,
      sourceKind: SourceKind.sibling,
      fanout: false,
      tie: 'zz',
      isolatedBit: true,
    );
    await module.build();
    final vectors = [
      for (final bit in ['0', '1', 'x', 'z'])
        Vector({
          'seed': LogicValue.ofString('000${bit}000000000000'),
          'other': 0,
        }, {
          'observed': LogicValue.ofString('0000${bit}zz0000'),
        }),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// submodule_output_mapping_test.dart
// Tests for submodule output mapping to packed parent bus bits
//
// 2026 September 25
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum ProducerKind { independent, multiport, hierarchical, custom }

enum AssignmentOrder { batch, forward, reverse }

enum MappingGuard {
  outputFanout,
  siblingFanout,
  repeatedBit,
  wholeBusFanout,
  renameableBus,
  reservedBus,
  namedBit,
  partial,
}

class BitStage extends Module {
  BitStage(Logic data) : super(name: 'stage') {
    data = addInput('data', data);
    addOutput('result') <= ~data;
  }
}

class HierarchicalStage extends Module {
  HierarchicalStage(Logic data) : super(name: 'hierarchical_stage') {
    data = addInput('data', data);
    addOutput('result') <= BitStage(data).output('result');
  }
}

class CustomStage extends Module with SystemVerilog {
  CustomStage(Logic data) : super(name: 'custom_stage') {
    data = addInput('data', data);
    addOutput('result') <= ~data;
  }

  @override
  String definitionVerilog(String definitionType) => '''
module $definitionType(input logic data, output logic result);
assign result = ~data;
endmodule
''';
}

class MultiportStage extends Module {
  MultiportStage(Logic data) : super(name: 'multiport_stage') {
    data = addInput('data', data, width: data.width);
    for (var index = 0; index < data.width; index++) {
      addOutput('result$index') <= ~data[index];
    }
  }
}

List<Logic> stageOutputs(Logic data, ProducerKind kind) {
  if (kind == ProducerKind.multiport) {
    final stage = MultiportStage(data);
    return [
      for (var index = 0; index < data.width; index++)
        stage.output('result$index'),
    ];
  }
  return [
    for (var index = 0; index < data.width; index++)
      switch (kind) {
        ProducerKind.independent => BitStage(data[index]).output('result'),
        ProducerKind.hierarchical =>
          HierarchicalStage(data[index]).output('result'),
        ProducerKind.custom => CustomStage(data[index]).output('result'),
        ProducerKind.multiport => throw StateError('Handled above'),
      },
  ];
}

void assignBits(Logic destination, List<Logic> bits, AssignmentOrder order) {
  if (order == AssignmentOrder.batch) {
    destination.assignSubset(bits);
  } else {
    final indices = List.generate(bits.length, (index) => index);
    for (final index
        in order == AssignmentOrder.reverse ? indices.reversed : indices) {
      destination.assignSubset([bits[index]], start: index);
    }
  }
}

class OutputMappingTop extends Module {
  OutputMappingTop({
    required int width,
    required ProducerKind producer,
    required AssignmentOrder order,
    required int aliasDepth,
  }) : super(name: 'output_mapping_top') {
    final data = addInput('data', Logic(width: width), width: width);
    final observed = addOutput('observed', width: width);
    var destination = observed;
    for (var depth = 0; depth < aliasDepth; depth++) {
      final alias = Logic(width: width, naming: Naming.mergeable);
      destination <= alias;
      destination = alias;
    }
    final results = stageOutputs(data, producer);
    assignBits(destination, results.reversed.toList(), order);
  }
}

class GuardedOutputTop extends Module {
  GuardedOutputTop({
    required MappingGuard guard,
    required ProducerKind producer,
    required AssignmentOrder order,
  }) : super(name: 'guarded_output_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final observed =
        addOutput('observed', width: guard == MappingGuard.partial ? 5 : 4);
    final results = stageOutputs(
        guard == MappingGuard.repeatedBit ? data.getRange(0, 3) : data,
        producer);
    var destination = observed;
    switch (guard) {
      case MappingGuard.outputFanout:
        addOutput('tap') <= results[1];
      case MappingGuard.siblingFanout:
        addOutput('tap') <= BitStage(results[1]).output('result');
      case MappingGuard.repeatedBit:
        results.add(results[1]);
      case MappingGuard.wholeBusFanout:
        addOutput('mirror', width: 4) <= observed;
      case MappingGuard.renameableBus:
      case MappingGuard.reservedBus:
        destination = Logic(
          width: 4,
          name: 'retained',
          naming: guard == MappingGuard.reservedBus
              ? Naming.reserved
              : Naming.renameable,
        );
        observed <= destination;
      case MappingGuard.namedBit:
        results[1] = results[1].named('retained', naming: Naming.reserved);
      case MappingGuard.partial:
        break;
    }
    assignBits(destination, results, order);
  }
}

class ConstantOutputTop extends Module {
  ConstantOutputTop({
    required String constant,
    required int constantIndex,
    required bool namedConstant,
    required AssignmentOrder order,
  }) : super(name: 'constant_output_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final observed = addOutput('observed', width: 5);
    final results = stageOutputs(data, ProducerKind.independent);
    Logic tie = Const(LogicValue.ofString(constant));
    if (namedConstant) {
      tie = tie.named('tie', naming: Naming.mergeable);
    }
    results.insert(constantIndex, tie);
    assignBits(observed, results, order);
  }
}

class WideStage extends Module {
  WideStage(Logic data) : super(name: 'wide_stage') {
    data = addInput('data', data, width: data.width);
    addOutput('wide_result', width: data.width) <= ~data;
  }
}

class MixedRangeTop extends Module {
  MixedRangeTop({
    required bool wideProducer,
    required bool fanout,
    required AssignmentOrder order,
  }) : super(name: 'mixed_range_top') {
    final data = addInput('data', Logic(width: 5), width: 5);
    final observed = addOutput('observed', width: 5);
    final low = BitStage(data[0]).output('result');
    final high = BitStage(data[4]).output('result');
    final middle = wideProducer
        ? WideStage(data.getRange(1, 4)).output('wide_result')
        : data.getRange(1, 4);
    assignBits(observed, [low, ...middle.elements, high], order);
    if (fanout) {
      addOutput('tap', width: 3) <= middle;
    }
  }
}

class OutputHierarchyTop extends Module {
  OutputHierarchyTop({required int unpackedDimensions, required bool slice})
      : super(name: 'output_hierarchy_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final inner = OutputMappingTop(
      width: 4,
      producer: ProducerKind.multiport,
      order: AssignmentOrder.reverse,
      aliasDepth: 3,
    );
    inner.inputSource('data') <= data;
    final observed = addOutputArray('observed',
        dimensions: slice ? [2] : [2, 2],
        numUnpackedDimensions: unpackedDimensions);
    observed <=
        (slice
            ? inner.output('observed').getRange(1, 3)
            : inner.output('observed'));
  }
}

String topBody(Module module) {
  final verilog = module.generateSynth();
  return verilog.substring(verilog.indexOf('module ${module.definitionName} '));
}

Iterable<LogicValue> inputPatterns(int width) sync* {
  for (var value = 0; value < 1 << width; value++) {
    yield LogicValue.ofInt(value, width);
  }
  for (var index = 0; index < width; index++) {
    for (final state in ['x', 'z']) {
      yield LogicValue.ofString([
        for (var bit = width - 1; bit >= 0; bit--)
          if (bit == index) state else (bit % 2).toString(),
      ].join());
    }
  }
}

String invertedBit(LogicValue input, int index) {
  final bit = input[index];
  return bit.isValid ? (bit.toInt() ^ 1).toString() : 'x';
}

void main() {
  setUp(Simulator.reset);

  group('independent outputs to packed parent bits', () {
    for (final producer in ProducerKind.values) {
      for (final order in AssignmentOrder.values) {
        for (final width in [2, 5]) {
          for (final aliasDepth in [0, 3]) {
            test(
                '${producer.name} ${order.name} '
                'width=$width aliases=$aliasDepth', () async {
              final module = OutputMappingTop(
                width: width,
                producer: producer,
                order: order,
                aliasDepth: aliasDepth,
              );
              await module.build();
              final body = topBody(module);
              for (var index = 0; index < width; index++) {
                expect(body, matches('\\.result\\d*\\(observed\\[$index\\]\\)'),
                    reason: body);
              }
              expect(body, isNot(matches(r'assign\s+observed\[')));
              if (producer != ProducerKind.custom) {
                expect(body, isNot(matches(r'logic\s+result\w*;')));
              }

              NetlistSynthesizer().synthesizeToJson(module);
              expect(topBody(module), body);

              final vectors = [
                for (final input in inputPatterns(width))
                  Vector({
                    'data': input
                  }, {
                    'observed': LogicValue.ofString([
                      for (var index = 0; index < width; index++)
                        invertedBit(input, index),
                    ].join()),
                  }),
              ];
              await SimCompare.checkFunctionalVector(module, vectors);
              SimCompare.checkIverilogVector(module, vectors);
            });
          }
        }
      }
    }
  });

  group('output mapping safety cross-products', () {
    for (final guard in MappingGuard.values) {
      for (final producer in [
        ProducerKind.independent,
        ProducerKind.multiport
      ]) {
        for (final order in [AssignmentOrder.batch, AssignmentOrder.reverse]) {
          test('${guard.name} ${producer.name} ${order.name}', () async {
            final module = GuardedOutputTop(
              guard: guard,
              producer: producer,
              order: order,
            );
            await module.build();
            final body = topBody(module);
            expect(body, isNot(matches(r'\.result\d*\(\)')), reason: body);
            if (guard == MappingGuard.renameableBus ||
                guard == MappingGuard.reservedBus ||
                guard == MappingGuard.partial) {
              expect(body, isNot(matches(r'\.result\d*\(observed\[')));
            } else {
              for (final index in [0, 2]) {
                expect(body,
                    matches('\\.result\\d*\\((observed|mirror)\\[$index\\]\\)'),
                    reason: body);
              }
            }
            if (guard == MappingGuard.renameableBus ||
                guard == MappingGuard.reservedBus) {
              expect(body, contains('logic [3:0] retained;'));
            }
            if (guard == MappingGuard.namedBit) {
              expect(body, contains('logic retained;'));
            }
            NetlistSynthesizer().synthesizeToJson(module);
            expect(topBody(module), body);

            final vectors = [
              for (final input in inputPatterns(4))
                Vector({
                  'data': input
                }, {
                  'observed': LogicValue.ofString([
                    if (guard == MappingGuard.partial) 'z',
                    for (var index = 3; index >= 0; index--)
                      invertedBit(
                          input,
                          guard == MappingGuard.repeatedBit && index == 3
                              ? 1
                              : index),
                  ].join()),
                  if (guard == MappingGuard.outputFanout)
                    'tap': LogicValue.ofString(invertedBit(input, 1)),
                  if (guard == MappingGuard.siblingFanout)
                    'tap': input[1].isValid ? input[1] : LogicValue.x,
                  if (guard == MappingGuard.wholeBusFanout) 'mirror': ~input,
                }),
            ];
            await SimCompare.checkFunctionalVector(module, vectors);
            SimCompare.checkIverilogVector(module, vectors);
          });
        }
      }
    }
  });

  group('constant position and four-state cross-products', () {
    for (final constant in ['0', '1', 'x', 'z']) {
      for (final constantIndex in [0, 2, 4]) {
        for (final namedConstant in [false, true]) {
          for (final order in [
            AssignmentOrder.batch,
            AssignmentOrder.reverse
          ]) {
            test(
                '$constant at $constantIndex '
                'named=$namedConstant ${order.name}', () async {
              final module = ConstantOutputTop(
                constant: constant,
                constantIndex: constantIndex,
                namedConstant: namedConstant,
                order: order,
              );
              await module.build();
              final body = topBody(module);
              expect(body, isNot(contains('.result()')), reason: body);
              if (constant != 'z') {
                for (final index in [0, 4]) {
                  if (index != constantIndex) {
                    expect(body, contains('.result(observed[$index])'),
                        reason: body);
                  }
                }
              }
              NetlistSynthesizer().synthesizeToJson(module);
              expect(topBody(module), body);
              final vectors = [
                for (final input in inputPatterns(4))
                  Vector({
                    'data': input
                  }, {
                    'observed': LogicValue.ofString([
                      for (var index = 4; index >= 0; index--)
                        if (index == constantIndex)
                          constant
                        else
                          invertedBit(
                              input, index > constantIndex ? index - 1 : index),
                    ].join()),
                  }),
              ];
              await SimCompare.checkFunctionalVector(module, vectors);
              SimCompare.checkIverilogVector(module, vectors);
            });
          }
        }
      }
    }
  });

  group('scalar producers beside packed ranges', () {
    for (final wideProducer in [false, true]) {
      for (final fanout in [false, true]) {
        for (final order in AssignmentOrder.values) {
          test('wide=$wideProducer fanout=$fanout ${order.name}', () async {
            final module = MixedRangeTop(
              wideProducer: wideProducer,
              fanout: fanout,
              order: order,
            );
            await module.build();
            final body = topBody(module);
            for (final index in [0, 4]) {
              expect(body, contains('.result(observed[$index])'), reason: body);
            }
            expect(body, isNot(contains('.wide_result()')));
            NetlistSynthesizer().synthesizeToJson(module);
            expect(topBody(module), body);
            final vectors = [
              for (final input in inputPatterns(5))
                Vector({
                  'data': input
                }, {
                  'observed': LogicValue.ofString([
                    for (var index = 4; index >= 0; index--)
                      if (wideProducer || index == 0 || index == 4)
                        invertedBit(input, index)
                      else
                        input[index].toString(includeWidth: false),
                  ].join()),
                  if (fanout)
                    'tap': wideProducer
                        ? ~input.getRange(1, 4)
                        : input.getRange(1, 4),
                }),
            ];
            await SimCompare.checkFunctionalVector(module, vectors);
            SimCompare.checkIverilogVector(module, vectors);
          });
        }
      }
    }
  });

  group('packed word boundaries and deep aliases', () {
    for (final width in [33, 65]) {
      for (final producer in [
        ProducerKind.independent,
        ProducerKind.multiport
      ]) {
        for (final aliasDepth in [0, 16]) {
          test('width=$width ${producer.name} aliases=$aliasDepth', () async {
            final module = OutputMappingTop(
              width: width,
              producer: producer,
              order: AssignmentOrder.reverse,
              aliasDepth: aliasDepth,
            );
            await module.build();
            final body = topBody(module);
            for (var index = 0; index < width; index++) {
              expect(body, matches('\\.result\\d*\\(observed\\[$index\\]\\)'),
                  reason: body);
            }
            NetlistSynthesizer().synthesizeToJson(module);
            expect(topBody(module), body);
            final inputs = [
              LogicValue.ofBigInt(BigInt.zero, width),
              LogicValue.ofBigInt((BigInt.one << width) - BigInt.one, width),
              for (var index = 0; index < width; index++)
                LogicValue.ofBigInt(BigInt.one << index, width),
              for (final index in [
                31,
                32,
                if (width > 64) ...[63, 64]
              ])
                for (final state in ['x', 'z'])
                  LogicValue.ofString([
                    for (var bit = width - 1; bit >= 0; bit--)
                      if (bit == index) state else (bit % 2).toString(),
                  ].join()),
            ];
            final vectors = [
              for (final input in inputs)
                Vector({
                  'data': input
                }, {
                  'observed': LogicValue.ofString([
                    for (var index = 0; index < width; index++)
                      invertedBit(input, index),
                  ].join()),
                }),
            ];
            await SimCompare.checkFunctionalVector(module, vectors);
            SimCompare.checkIverilogVector(module, vectors);
          });
        }
      }
    }
  });

  group('optimized child in array hierarchy', () {
    for (final slice in [false, true]) {
      for (final unpackedDimensions in [0, 1, if (!slice) 2]) {
        test('slice=$slice unpacked=$unpackedDimensions', () async {
          final module = OutputHierarchyTop(
            unpackedDimensions: unpackedDimensions,
            slice: slice,
          );
          await module.build();
          final vectors = [
            for (final input in inputPatterns(4))
              Vector({
                'data': input
              }, {
                'observed': LogicValue.ofString([
                  for (var index = slice ? 1 : 0;
                      index < (slice ? 3 : 4);
                      index++)
                    invertedBit(input, index),
                ].join()),
              }),
          ];
          await SimCompare.checkFunctionalVector(module, vectors);
          if (unpackedDimensions == 0) {
            SimCompare.checkIverilogVector(module, vectors);
          } else {
            SimCompare.checkVerilatorVector(module, vectors.take(16).toList());
          }
        });
      }
    }
  });
}

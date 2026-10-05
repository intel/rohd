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

enum AssignmentOrder { batch, forward, reverse, swizzle, rswizzle }

enum SwizzleUse { slice, wholeAndSlice, partialDestination, filledDestination }

enum OperandRanges { slice, reordered, overlapping, nested }

enum MappingGuard {
  outputFanout,
  siblingFanout,
  busFanout,
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

class CustomMultiportStage extends Module with SystemVerilog {
  @override
  final bool acceptsEmptyPortConnections;

  CustomMultiportStage(Logic data, {required this.acceptsEmptyPortConnections})
      : super(name: 'custom_multiport_stage') {
    data = addInput('data', data, width: 3);
    for (var index = 0; index < 3; index++) {
      addOutput('result$index') <= ~data[index];
    }
  }

  @override
  String definitionVerilog(String definitionType) => '''
module $definitionType(input logic [2:0] data,
    output logic result0, result1, result2);
assign result0 = ~data[0];
assign result1 = ~data[1];
assign result2 = ~data[2];
endmodule
''';
}

class CustomRetentionTop extends Module {
  CustomRetentionTop({
    required bool acceptsEmptyPortConnections,
    required bool fanout,
    required AssignmentOrder order,
    bool legacy = false,
  }) : super(name: 'custom_retention_top') {
    final data = addInput('data', Logic(width: 3), width: 3);
    final stage = legacy
        ? LegacyMultiportStage(data)
        : CustomMultiportStage(data,
            acceptsEmptyPortConnections: acceptsEmptyPortConnections);
    final observed = addOutput('observed', width: 2);
    assignBits(
        observed, [stage.output('result0'), stage.output('result1')], order);
    if (fanout) {
      addOutput('tap') <= BitStage(stage.output('result1')).output('result');
    }
  }
}

// ignore: deprecated_member_use_from_same_package - backwards compatibility with CustomSystemVerilog
class LegacyMultiportStage extends MultiportStage with CustomSystemVerilog {
  LegacyMultiportStage(super.data);

  @override
  String instantiationVerilog(String instanceType, String instanceName,
          Map<String, String> inputs, Map<String, String> outputs) =>
      List.generate(3, (index) {
        final output = outputs['result$index'];
        return 'not ${instanceName}_$index('
            '$output, ${inputs['data']}[$index]);';
      }).join('\n');
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
  if (order == AssignmentOrder.swizzle) {
    destination <= bits.reversed.toList().swizzle();
  } else if (order == AssignmentOrder.rswizzle) {
    destination <= bits.rswizzle();
  } else if (order == AssignmentOrder.batch) {
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
    Naming? bitNaming,
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
    assignBits(
        destination,
        [
          for (final (index, result) in results.reversed.indexed)
            if (bitNaming == null)
              result
            else
              result.named('bit_alias$index', naming: bitNaming),
        ],
        order);
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
      case MappingGuard.busFanout:
        assignBits(addOutput('secondary', width: 3),
            [results[1], Const(0), Const(1)], order);
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

class CustomWideStage extends WideStage with SystemVerilog {
  CustomWideStage(super.data);

  @override
  String definitionVerilog(String definitionType) => '''
module $definitionType(input logic [${input('data').width - 1}:0] data,
    output logic [${input('data').width - 1}:0] wide_result);
assign wide_result = ~data;
endmodule
''';
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
    assignBits(
        observed,
        [
          low,
          if (order == AssignmentOrder.swizzle ||
              order == AssignmentOrder.rswizzle)
            middle
          else
            ...middle.elements,
          high,
        ],
        order);
    if (fanout) {
      addOutput('tap', width: 3) <= middle;
    }
  }
}

class SlicedSwizzleTop extends Module {
  SlicedSwizzleTop({
    required ProducerKind producer,
    required AssignmentOrder order,
    required Naming naming,
    required SwizzleUse use,
    required bool fanout,
    required int lower,
    required int upper,
  }) : super(name: 'sliced_swizzle_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final sources = stageOutputs(data, producer);
    final operands = [
      for (final (index, source) in sources.indexed)
        source.named('operand$index', naming: naming),
    ];
    final combined = order == AssignmentOrder.swizzle
        ? operands.swizzle()
        : operands.rswizzle();
    final selected = combined.getRange(lower, upper);
    final partial = use == SwizzleUse.partialDestination ||
        use == SwizzleUse.filledDestination;
    final observed =
        addOutput('observed', width: upper - lower + (partial ? 2 : 0));
    if (partial) {
      observed.assignSubset(selected.elements, start: 1);
      if (use == SwizzleUse.filledDestination) {
        observed.assignSubset([Const(0)]);
        observed.assignSubset([Const(1)], start: observed.width - 1);
      }
    } else {
      observed <= selected;
    }
    if (use == SwizzleUse.wholeAndSlice) {
      addOutput('whole', width: 4) <= combined;
    }
    if (fanout) {
      addOutput('tap') <= BitStage(operands[1]).output('result');
    }
  }
}

class RangeOperandSwizzleTop extends Module {
  RangeOperandSwizzleTop({
    required ProducerKind producer,
    required AssignmentOrder order,
    required Naming naming,
    required OperandRanges ranges,
    required String constant,
    required int constantPosition,
    required bool fanout,
  }) : super(name: 'range_operand_swizzle_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final sources = stageOutputs(data, producer);
    final wideStage = producer == ProducerKind.custom
        ? CustomWideStage(data)
        : WideStage(data);
    final wide =
        wideStage.output('wide_result').named('wide_alias', naming: naming);
    final pieces = switch (ranges) {
      OperandRanges.slice => [wide.getRange(1, 3)],
      OperandRanges.reordered => [wide.getRange(2, 4), wide.getRange(0, 2)],
      OperandRanges.overlapping => [wide.getRange(0, 2), wide.getRange(1, 3)],
      OperandRanges.nested => [wide.getRange(1, 4).getRange(1, 2)],
    };
    final low = sources.first.named('low_alias', naming: naming);
    final operands = [
      low,
      for (final (index, piece) in pieces.indexed)
        piece.named('range$index', naming: naming),
      sources.last.named('high_alias', naming: naming),
    ];
    operands.insert(constantPosition < 0 ? operands.length : constantPosition,
        Const(LogicValue.ofString(constant)).named('tie', naming: naming));
    final combined = order == AssignmentOrder.swizzle
        ? operands.swizzle()
        : operands.rswizzle();
    addOutput('observed', width: combined.width) <= combined;
    if (fanout) {
      addOutput('wide_tap', width: 4) <= wide;
      addOutput('bit_tap') <= BitStage(low).output('result');
      addOutput('window', width: combined.width - 2) <=
          combined.getRange(1, combined.width - 1);
    }
  }
}

class OutputHierarchyTop extends Module {
  OutputHierarchyTop({
    required int unpackedDimensions,
    required bool slice,
    required AssignmentOrder order,
  }) : super(name: 'output_hierarchy_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final inner = OutputMappingTop(
      width: 4,
      producer: ProducerKind.multiport,
      order: order,
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

Iterable<LogicValue> fourStateInputPatterns(int width,
    {bool exhaustive = false}) sync* {
  if (!exhaustive) {
    yield* inputPatterns(width);
    yield LogicValue.filled(width, LogicValue.x);
    yield LogicValue.filled(width, LogicValue.z);
    for (final inverted in [false, true]) {
      yield LogicValue.ofString([
        for (var bit = width - 1; bit >= 0; bit--)
          if ((bit.isEven) != inverted) 'x' else 'z',
      ].join());
    }
    return;
  }
  const states = ['0', '1', 'x', 'z'];
  for (var value = 0; value < 1 << (2 * width); value++) {
    yield LogicValue.ofString([
      for (var bit = width - 1; bit >= 0; bit--)
        states[(value >> (2 * bit)) & 3],
    ].join());
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
              expect(body, isNot(matches(r'logic\s+result\w*;')),
                  reason: 'Directly mapped outputs should not leave unused '
                      'intermediate declarations.\n$body');
            });
          }
        }
      }
    }
  });

  group('concatenated output alias naming', () {
    for (final producer in [ProducerKind.independent, ProducerKind.custom]) {
      for (final order in [AssignmentOrder.swizzle, AssignmentOrder.rswizzle]) {
        for (final naming in Naming.values) {
          test('${producer.name} ${order.name} ${naming.name}', () async {
            final module = OutputMappingTop(
              width: 3,
              producer: producer,
              order: order,
              aliasDepth: 3,
              bitNaming: naming,
            );
            await module.build();
            final body = topBody(module);
            final preserve =
                naming == Naming.reserved || naming == Naming.renameable;
            for (var index = 0; index < 3; index++) {
              if (preserve) {
                expect(body, contains('logic bit_alias$index;'));
                expect(body, contains('.result(bit_alias$index)'));
              } else {
                expect(body, contains('.result(observed[$index])'),
                    reason: body);
                expect(body, isNot(contains('logic bit_alias$index;')));
              }
            }
            NetlistSynthesizer().synthesizeToJson(module);
            expect(topBody(module), body);
            final vectors = [
              for (final input in inputPatterns(3))
                Vector({
                  'data': input
                }, {
                  'observed': LogicValue.ofString([
                    for (var index = 0; index < 3; index++)
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

  group('output mapping safety cross-products', () {
    for (final guard in MappingGuard.values) {
      for (final producer in [
        ProducerKind.independent,
        ProducerKind.multiport,
        ProducerKind.custom,
      ]) {
        for (final order in [
          AssignmentOrder.batch,
          AssignmentOrder.reverse,
          if (guard != MappingGuard.partial) ...[
            AssignmentOrder.swizzle,
            AssignmentOrder.rswizzle,
          ],
        ]) {
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
                  if (guard == MappingGuard.busFanout)
                    'secondary':
                        LogicValue.ofString('10${invertedBit(input, 1)}'),
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

  group('custom output declaration retention', () {
    for (final (legacy, acceptsEmptyPortConnections) in [
      (false, false),
      (false, true),
      (true, false),
    ]) {
      for (final fanout in [false, true]) {
        for (final order in AssignmentOrder.values) {
          test(
              'legacy=$legacy empty=$acceptsEmptyPortConnections '
              'fanout=$fanout ${order.name}', () async {
            final module = CustomRetentionTop(
              acceptsEmptyPortConnections: acceptsEmptyPortConnections,
              fanout: fanout,
              order: order,
              legacy: legacy,
            );
            await module.build();
            final body = topBody(module);
            String connection(int index, String target) =>
                legacy ? '($target, data[$index])' : '.result$index($target)';

            expect(body, contains(connection(0, 'observed[0]')));
            expect(body, isNot(contains('logic result0;')));
            if (fanout) {
              expect(body, contains('logic result1;'));
              expect(body, contains(connection(1, 'result1')));
            } else {
              expect(body, isNot(contains('logic result1;')));
              expect(body, contains(connection(1, 'observed[1]')));
            }
            if (acceptsEmptyPortConnections) {
              expect(body, contains('.result2()'));
              expect(body, isNot(contains('logic result2;')));
            } else {
              expect(body, contains(connection(2, 'result2')));
              expect(body, contains('logic result2;'));
            }
            NetlistSynthesizer().synthesizeToJson(module);
            expect(topBody(module), body);

            final vectors = [
              for (final input in inputPatterns(3))
                Vector({
                  'data': input
                }, {
                  'observed': ~input.getRange(0, 2),
                  if (fanout) 'tap': input[1].isValid ? input[1] : LogicValue.x,
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
            AssignmentOrder.reverse,
            AssignmentOrder.swizzle,
            AssignmentOrder.rswizzle,
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
                for (var index = 0; index < 5; index++) {
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

  group('sliced swizzle equivalence cross-products', () {
    for (final producer in ProducerKind.values) {
      for (final order in [AssignmentOrder.swizzle, AssignmentOrder.rswizzle]) {
        for (final naming in Naming.values) {
          for (final use in SwizzleUse.values) {
            for (final fanout in [false, true]) {
              for (final (lower, upper) in [(0, 1), (1, 3), (3, 4)]) {
                // Cover all names on independent producers; exercise other
                // producer kinds with mergeable names to bound the matrix.
                if (producer != ProducerKind.independent &&
                    naming != Naming.mergeable) {
                  continue;
                }
                // The middle slice covers naming and producer variations;
                // boundary slices still cover every use, order, and fanout.
                if (lower != 1 &&
                    (producer != ProducerKind.independent ||
                        naming != Naming.mergeable)) {
                  continue;
                }
                test(
                    '${producer.name} ${order.name} ${naming.name} '
                    '${use.name} fanout=$fanout [$lower:$upper]', () async {
                  final module = SlicedSwizzleTop(
                    producer: producer,
                    order: order,
                    naming: naming,
                    use: use,
                    fanout: fanout,
                    lower: lower,
                    upper: upper,
                  );
                  await module.build();
                  final body = topBody(module);
                  printOnFailure(body);
                  NetlistSynthesizer().synthesizeToJson(module);
                  expect(topBody(module), body);
                  final vectors = [
                    for (final input in fourStateInputPatterns(4,
                        exhaustive: producer == ProducerKind.independent &&
                            order == AssignmentOrder.rswizzle &&
                            naming == Naming.mergeable &&
                            use == SwizzleUse.wholeAndSlice &&
                            fanout))
                      Vector({
                        'data': input
                      }, {
                        'observed': LogicValue.ofString([
                          if (use == SwizzleUse.partialDestination) 'z',
                          if (use == SwizzleUse.filledDestination) '1',
                          for (var bit = upper - 1; bit >= lower; bit--)
                            invertedBit(
                                input,
                                order == AssignmentOrder.swizzle
                                    ? 3 - bit
                                    : bit),
                          if (use == SwizzleUse.partialDestination) 'z',
                          if (use == SwizzleUse.filledDestination) '0',
                        ].join()),
                        if (use == SwizzleUse.wholeAndSlice)
                          'whole': LogicValue.ofString([
                            for (var bit = 3; bit >= 0; bit--)
                              invertedBit(
                                  input,
                                  order == AssignmentOrder.swizzle
                                      ? 3 - bit
                                      : bit),
                          ].join()),
                        if (fanout)
                          'tap': input[1].isValid ? input[1] : LogicValue.x,
                      }),
                  ];
                  await SimCompare.checkFunctionalVector(module, vectors);
                  SimCompare.checkIverilogVector(module, vectors);
                });
              }
            }
          }
        }
      }
    }
  });

  for (final filled in [false, true]) {
    test('partial destination of a swizzle slice filled=$filled', () async {
      final module = SlicedSwizzleTop(
        producer: ProducerKind.independent,
        order: AssignmentOrder.rswizzle,
        naming: Naming.mergeable,
        use: filled
            ? SwizzleUse.filledDestination
            : SwizzleUse.partialDestination,
        fanout: false,
        lower: 1,
        upper: 3,
      );
      await module.build();
      printOnFailure(topBody(module));
      final vectors = [
        Vector({'data': 0},
            {'observed': LogicValue.ofString(filled ? '1110' : 'z11z')}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);
    });
  }

  test('preserved Z constant beside child output slices', () async {
    final module = RangeOperandSwizzleTop(
      producer: ProducerKind.custom,
      order: AssignmentOrder.rswizzle,
      naming: Naming.reserved,
      ranges: OperandRanges.slice,
      constant: 'z',
      constantPosition: 1,
      fanout: false,
    );
    await module.build();
    printOnFailure(topBody(module));
    final vectors = [
      Vector({'data': 0}, {'observed': LogicValue.ofString('111z1')}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  group('range operand equivalence cross-products', () {
    for (final producer in [ProducerKind.independent, ProducerKind.custom]) {
      for (final order in [AssignmentOrder.swizzle, AssignmentOrder.rswizzle]) {
        for (final naming in Naming.values) {
          for (final ranges in OperandRanges.values) {
            for (final fanout in [false, true]) {
              for (final constant in [
                '0',
                '1',
                'x',
                'z',
              ]) {
                for (final constantPosition in [0, 1, -1]) {
                  // Cover every topology/name/fanout combination with middle Z.
                  final topologyCase = constant == 'z' && constantPosition == 1;
                  // Sweep all constant states and positions on one topology.
                  final constantCase = producer == ProducerKind.independent &&
                      naming == Naming.mergeable &&
                      !fanout;
                  // Keep all preserved-Z positions for the pruning regression.
                  final preservedFloatingCase = constant == 'z' &&
                      (naming == Naming.reserved ||
                          naming == Naming.renameable) &&
                      !fanout;
                  // Bound runtime by omitting the remaining cross-products.
                  if (!topologyCase &&
                      !constantCase &&
                      !preservedFloatingCase) {
                    continue;
                  }
                  test(
                      '${producer.name} ${order.name} ${naming.name} '
                      '${ranges.name} fanout=$fanout '
                      '$constant at $constantPosition', () async {
                    final module = RangeOperandSwizzleTop(
                      producer: producer,
                      order: order,
                      naming: naming,
                      ranges: ranges,
                      constant: constant,
                      constantPosition: constantPosition,
                      fanout: fanout,
                    );
                    await module.build();
                    final body = topBody(module);
                    printOnFailure(body);
                    if (naming == Naming.reserved ||
                        naming == Naming.renameable) {
                      expect(body, contains('wide_alias'));
                      expect(body, contains('range0'));
                    } else if (constantPosition != -1) {
                      expect(body, matches(r'\.result\(observed\[\d+\]\)'));
                    }
                    if (topologyCase) {
                      NetlistSynthesizer().synthesizeToJson(module);
                      expect(topBody(module), body);
                    }
                    final sourceIndices = switch (ranges) {
                      OperandRanges.slice => [
                          [1, 2]
                        ],
                      OperandRanges.reordered => [
                          [2, 3],
                          [0, 1]
                        ],
                      OperandRanges.overlapping => [
                          [0, 1],
                          [1, 2]
                        ],
                      OperandRanges.nested => [
                          [2]
                        ],
                    };
                    final vectors = <Vector>[];
                    for (final input in fourStateInputPatterns(4,
                        exhaustive: producer == ProducerKind.custom &&
                            order == AssignmentOrder.rswizzle &&
                            naming == Naming.mergeable &&
                            !fanout &&
                            constant == 'z' &&
                            constantPosition == 1)) {
                      final expectedOperands = [
                        [invertedBit(input, 0)],
                        for (final indices in sourceIndices)
                          [
                            for (final index in indices)
                              invertedBit(input, index)
                          ],
                        [invertedBit(input, 3)],
                      ];
                      expectedOperands.insert(
                          constantPosition < 0
                              ? expectedOperands.length
                              : constantPosition,
                          [constant]);
                      final expectedBits = (order == AssignmentOrder.swizzle
                              ? expectedOperands.reversed
                              : expectedOperands)
                          .expand((operand) => operand)
                          .toList();
                      vectors.add(Vector({
                        'data': input
                      }, {
                        'observed':
                            LogicValue.ofString(expectedBits.reversed.join()),
                        if (fanout) ...{
                          'wide_tap': ~input,
                          'bit_tap': input[0].isValid ? input[0] : LogicValue.x,
                          'window': LogicValue.ofString(expectedBits
                              .sublist(1, expectedBits.length - 1)
                              .reversed
                              .join()),
                        },
                      }));
                    }
                    await SimCompare.checkFunctionalVector(module, vectors);
                    SimCompare.checkIverilogVector(module, vectors);
                  });
                }
              }
            }
          }
        }
      }
    }
  });

  group('packed word boundaries and deep aliases', () {
    for (final (width, order) in [
      for (final width in [33, 65])
        for (final order in [
          AssignmentOrder.reverse,
          AssignmentOrder.swizzle,
          AssignmentOrder.rswizzle,
        ])
          (width, order),
    ]) {
      for (final producer in [
        ProducerKind.independent,
        ProducerKind.multiport
      ]) {
        for (final aliasDepth in [0, 16]) {
          test(
              'width=$width ${producer.name} ${order.name} aliases=$aliasDepth',
              () async {
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
    for (final (slice, order) in [
      for (final slice in [false, true])
        for (final order in [
          AssignmentOrder.reverse,
          AssignmentOrder.swizzle,
          AssignmentOrder.rswizzle,
        ])
          (slice, order),
    ]) {
      for (final unpackedDimensions in [0, 1, if (!slice) 2]) {
        final unpackedOrder = slice
            ? AssignmentOrder.rswizzle
            : unpackedDimensions == 1
                ? AssignmentOrder.reverse
                : AssignmentOrder.swizzle;
        if (unpackedDimensions != 0 && order != unpackedOrder) {
          continue;
        }
        test('slice=$slice unpacked=$unpackedDimensions ${order.name}',
            () async {
          final module = OutputHierarchyTop(
            unpackedDimensions: unpackedDimensions,
            slice: slice,
            order: order,
          );
          await module.build();
          final body = topBody(module);
          printOnFailure(body);
          NetlistSynthesizer().synthesizeToJson(module);
          expect(topBody(module), body);
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

// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flop.dart
// Definition for flip flops.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Constructs a positive edge triggered flip flop on [clk].
///
/// It returns [FlipFlop.q].
///
/// When the optional [en] is provided, an additional input will be created for
/// flop. If optional [en] is high or not provided, output will vary as per
/// input[d]. For low [en], output remains frozen irrespective of input [d].
///
/// When the optional [reset] is provided, the flop will be reset (active-high).
/// If no [resetValue] is provided, the reset value is always `0`. Otherwise,
/// it will reset to the provided [resetValue].
///
/// If [asyncReset] is true, the [reset] signal (if provided) will be treated
/// as an async reset. If [asyncReset] is false, the reset signal will be
/// treated as synchronous.
Logic flop(
  Logic clk,
  Logic d, {
  Logic? en,
  Logic? reset,
  dynamic resetValue,
  bool asyncReset = false,
}) =>
    FlipFlop(
      clk,
      d,
      en: en,
      reset: reset,
      resetValue: resetValue,
      asyncReset: asyncReset,
    ).q;

/// A flip-flop with an output represented by [LogicType].
///
/// Implementations decide how an input is normalized into the promised output
/// type. [FlipFlop] produces an ordinary [Logic], while
/// [StructureFlipFlop] preserves matching structure and array boundaries.
abstract class TypedFlipFlop<LogicType extends Logic>
    extends TypedOp<LogicType> {
  /// Registered output.
  LogicType get q;

  @override
  LogicType get out => q;

  /// Creates a typed flip-flop implementation.
  TypedFlipFlop({
    super.name = 'typed_flip_flop',
    super.reserveName,
    super.definitionName,
    super.reserveDefinitionName,
  });
}

/// Represents a single flip-flop with no reset.
class FlipFlop extends TypedFlipFlop<Logic> with SystemVerilog {
  /// Name for the enable input of this flop
  final String _enName = Naming.unpreferredName('en');

  /// Name for the clk of this flop.
  final String _clkName = Naming.unpreferredName('clk');

  /// Name for the input of this flop.
  final String _dName = Naming.unpreferredName('d');

  /// Name for the output of this flop.
  final String _qName = Naming.unpreferredName('q');

  /// Name for the reset of this flop.
  final String _resetName = Naming.unpreferredName('reset');

  /// Name for the reset value of this flop.
  final String _resetValueName = Naming.unpreferredName('resetValue');

  /// The clock, posedge triggered.
  late final Logic _clk = input(_clkName);

  /// Optional enable input to the flop.
  ///
  /// If enable is  high or enable is not provided then flop output will vary
  /// on the basis of clock [_clk] and input [_d]. If enable is low, then
  /// output of the flop remains frozen irrespective of the input [_d].
  late final Logic? _en = tryInput(_enName);

  /// Optional reset input to the flop.
  late final Logic? _reset = tryInput(_resetName);

  /// The input to the flop.
  late final Logic _d = input(_dName);

  /// The output of the flop.
  @override
  late final Logic q = output(_qName);

  /// The reset value for this flop, if it was a port.
  Logic? _resetValuePort;

  /// The reset value for this flop, if it was a constant.
  ///
  /// Only initialized if a constant value is provided.
  late LogicValue _resetValueConst;

  /// Indicates whether provided `reset` signals should be treated as an async
  /// reset. If no `reset` is provided, this will have no effect.
  final bool asyncReset;

  /// The constant reset value, or `null` when reset is absent or data-driven.
  LogicValue? get constantResetValue =>
      _reset == null || _resetValuePort != null ? null : _resetValueConst;

  /// Constructs a flip flop which is positive edge triggered on [clk].
  ///
  /// When optional [en] is provided, an additional input will be created for
  /// flop. If optional [en] is high or not provided, output will vary as per
  /// input[d]. For low [en], output remains frozen irrespective of input [d]
  ///
  /// When the optional [reset] is provided, the flop will be reset active-high.
  /// If no [resetValue] is provided, the reset value is always `0`. Otherwise,
  /// it will reset to the provided [resetValue]. The type of [resetValue] must
  /// be a valid driver of a [ConditionalAssign] (e.g. [Logic], [LogicValue],
  /// [int], etc.).
  ///
  /// If [asyncReset] is true, the [reset] signal (if provided) will be treated
  /// as an async reset. If [asyncReset] is false, the reset signal will be
  /// treated as synchronous.
  FlipFlop(
    Logic clk,
    Logic d, {
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    this.asyncReset = false,
    super.name = 'flipflop',
  }) {
    if (clk.width != 1) {
      throw Exception('clk must be 1 bit');
    }

    addInput(_clkName, clk);
    addInput(_dName, d, width: d.width);
    addOutput(_qName, width: d.width);

    if (en != null) {
      addInput(_enName, en);
    }

    if (reset != null) {
      addInput(_resetName, reset);

      if (resetValue != null && resetValue is Logic) {
        _resetValuePort = addInput(_resetValueName, resetValue, width: d.width);
      } else {
        _resetValueConst = LogicValue.of(resetValue ?? 0, width: d.width);
      }
    }

    _setup();
  }

  /// Performs setup for custom functional behavior.
  void _setup() {
    var contents = [q < _d];

    final en = _en;
    if (en != null) {
      contents = [If(en, then: contents)];
    }

    Sequential(
      _clk,
      contents,
      reset: _reset,
      asyncReset: asyncReset,
      resetValues:
          _reset != null ? {q: _resetValuePort ?? _resetValueConst} : null,
    );
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    var expectedInputs = 2;
    if (_en != null) {
      expectedInputs++;
    }
    if (_reset != null) {
      expectedInputs++;
    }
    if (_resetValuePort != null) {
      expectedInputs++;
    }

    assert(
      ports.length == expectedInputs + 1,
      'FlipFlop has exactly $expectedInputs inputs and one output.',
    );

    final clk = ports[_clkName]!;
    final d = ports[_dName]!;
    final q = ports[_qName]!;
    final en = _en != null ? ports[_enName]! : null;
    final reset = _reset != null ? ports[_resetName]! : null;

    final triggerString = [
      clk,
      if (reset != null && asyncReset) reset,
    ].map((e) => 'posedge $e').join(' or ');

    final svBuffer = StringBuffer('always_ff @($triggerString) ');

    if (_reset != null) {
      final resetValueString = _resetValuePort != null
          ? ports[_resetValueName]!
          : _resetValueConst.toString();
      svBuffer.write('if(${reset!}) $q <= $resetValueString; else ');
    }

    if (_en != null) {
      svBuffer.write('if(${en!}) ');
    }

    svBuffer.write('$q <= $d;  // $instanceName');

    return svBuffer.toString();
  }
}

String _structureFlipFlopResetIdentity(
  LogicStructure structure,
  bool hasReset,
  bool hasResetPort,
  dynamic resetValue,
) {
  if (!hasReset) {
    return 'N';
  }
  if (hasResetPort) {
    return 'RP';
  }
  final value = LogicValue.of(resetValue ?? 0, width: structure.width);
  return 'RC${value.toRadixString(includeWidth: false, sepChar: '')}';
}

String _structureFlipFlopDefinitionName(
  LogicStructure structure, {
  required bool hasEnable,
  required bool hasReset,
  required bool hasResetPort,
  required dynamic resetValue,
  required bool asyncReset,
}) =>
    'StructureFlipFlop_${logicStructureShapeSignature(structure)}_'
    '${hasEnable ? 'E' : 'N'}_'
    '${_structureFlipFlopResetIdentity(
      structure,
      hasReset,
      hasResetPort,
      resetValue,
    )}_'
    '${asyncReset ? 'A' : 'S'}';

/// A flip-flop that preserves a concrete [LogicStructure] type.
///
/// Each structure leaf is registered independently with common clock, enable,
/// and reset controls. A [Logic] reset value is interpreted in the same packed
/// leaf order as [LogicStructure.packed]. A structured reset value must match
/// the input structure's recursive shape.
class StructureFlipFlop<LogicType extends LogicStructure>
    extends TypedFlipFlop<LogicType> {
  /// Indicates whether the reset is asynchronous.
  final bool asyncReset;

  /// Constant packed reset value, or `null` when reset is absent or driven by
  /// a [Logic] input.
  final LogicValue? constantResetValue;

  @override
  late final LogicType q;

  /// Creates a structure-preserving flip-flop.
  StructureFlipFlop(
    Logic clk,
    LogicType d, {
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    this.asyncReset = false,
    super.name = 'structure_flip_flop',
  })  : constantResetValue = reset != null && resetValue is! Logic
            ? LogicValue.of(resetValue ?? 0, width: d.width)
            : null,
        super(
          definitionName: _structureFlipFlopDefinitionName(
            d,
            hasEnable: en != null,
            hasReset: reset != null,
            hasResetPort: reset != null && resetValue is Logic,
            resetValue: resetValue,
            asyncReset: asyncReset,
          ),
        ) {
    if (clk.width != 1) {
      throw PortWidthMismatchException(clk, 1);
    }
    if (en != null && en.width != 1) {
      throw PortWidthMismatchException(en, 1);
    }
    if (reset != null && reset.width != 1) {
      throw PortWidthMismatchException(reset, 1);
    }
    if (resetValue is Logic) {
      if (resetValue.width != d.width) {
        throw PortWidthMismatchException.equalWidth(resetValue, d);
      }
      if (resetValue is LogicStructure) {
        validateMatchingLogicStructure(
          resetValue,
          d,
          operation: 'StructureFlipFlop reset',
        );
      }
    }

    LogicType cloneOutput({String name = 'q'}) => typedClone(d, name: name);

    final localClk = addInput('clk', clk);
    final localD = addTypedInput('d', d);
    final localEnable = en == null ? null : addInput('en', en);
    final localReset = reset == null ? null : addInput('reset', reset);
    final localResetValue = reset != null && resetValue is Logic
        ? addInput('resetValue', resetValue, width: d.width)
        : null;
    q = addTypedOutput('q', cloneOutput);

    var offset = 0;
    for (var index = 0; index < q.leafElements.length; index++) {
      final width = q.leafElements[index].width;
      final dynamic leafResetValue = localResetValue != null
          ? localResetValue.getRange(offset, offset + width)
          : constantResetValue?.getRange(offset, offset + width);
      q.leafElements[index] <=
          flop(
            localClk,
            localD.leafElements[index],
            en: localEnable,
            reset: localReset,
            resetValue: leafResetValue,
            asyncReset: asyncReset,
          );
      offset += width;
    }
  }
}

/// Constructs a positive-edge-triggered structure-preserving flip-flop.
LogicType typedFlop<LogicType extends LogicStructure>(
  Logic clk,
  LogicType d, {
  Logic? en,
  Logic? reset,
  dynamic resetValue,
  bool asyncReset = false,
}) =>
    StructureFlipFlop<LogicType>(
      clk,
      d,
      en: en,
      reset: reset,
      resetValue: resetValue,
      asyncReset: asyncReset,
    ).q;

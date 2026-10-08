// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flop.dart
// Definition for flip flops.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/operation_utils.dart';

/// Constructs a positive-edge-triggered flip-flop preserving [LogicType].
///
/// The input [d] supplies the output representation when [outputGenerator] is
/// omitted. Request `<Logic>` explicitly to normalize a plain [Const] or
/// [LogicNet] source into a driveable scalar result.
LogicType flop<LogicType extends Logic>(
  Logic clk,
  LogicType d, {
  Logic? en,
  Logic? reset,
  dynamic resetValue,
  bool asyncReset = false,
  LogicType Function({String? name})? outputGenerator,
}) =>
    FlipFlop<LogicType>(
      clk,
      d,
      en: en,
      reset: reset,
      resetValue: resetValue,
      asyncReset: asyncReset,
      outputGenerator: outputGenerator,
    ).q;

/// A positive-edge-triggered flip-flop preserving `LogicType`.
///
/// The returned `q` is created from `d`'s clone by default, or from
/// `outputGenerator` when supplied. Dynamic operation outputs must be
/// driveable, so a concrete [Const] or [LogicNet] result type is rejected.
class FlipFlop<LogicType extends Logic> extends Module {
  /// Registered output.
  LogicType get q => _scalarQ;

  late final LogicType _scalarQ;

  /// Alias for [q] shared with other single-output operations.
  LogicType get out => q;

  /// Indicates whether reset is asynchronous.
  bool get asyncReset => _scalarAsyncReset;

  late final bool _scalarAsyncReset;

  /// Constant packed reset value, when one is used.
  LogicValue? get constantResetValue => _scalarConstantResetValue;

  late final LogicValue? _scalarConstantResetValue;

  /// Constructs a flip-flop preserving [LogicType].
  factory FlipFlop(
    Logic clk,
    LogicType d, {
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    bool asyncReset = false,
    LogicType Function({String? name})? outputGenerator,
    String name = 'flipflop',
  }) {
    if (clk.width != 1) {
      throw PortWidthMismatchException(clk, 1);
    }
    if (en != null && en.width != 1) {
      throw PortWidthMismatchException(en, 1);
    }
    if (reset != null && reset.width != 1) {
      throw PortWidthMismatchException(reset, 1);
    }

    final outputSchema = createOperationOutput<LogicType>(
      width: d.width,
      name: 'q',
      operation: 'FlipFlop<$LogicType>',
      prototype: d,
      outputGenerator: outputGenerator,
    );
    validateOperationSource(d, outputSchema, operation: 'FlipFlop d');

    if (resetValue is Logic && resetValue.width != outputSchema.width) {
      throw PortWidthMismatchException.equalWidth(resetValue, outputSchema);
    }
    if (resetValue is LogicStructure && outputSchema is LogicStructure) {
      validateMatchingLogicStructure(
        resetValue,
        outputSchema,
        operation: 'FlipFlop reset',
      );
    }

    if (LogicType == Logic) {
      return _ScalarFlipFlop(
        clk,
        d,
        outputSchema as Logic,
        en: en,
        reset: reset,
        resetValue: resetValue,
        asyncReset: asyncReset,
        usesOutputGenerator: outputGenerator != null,
        name: name,
      ) as FlipFlop<LogicType>;
    }
    if (d is LogicStructure) {
      return _StructuredFlipFlop<LogicType>(
        clk,
        d,
        outputSchema,
        en: en,
        reset: reset,
        resetValue: resetValue,
        asyncReset: asyncReset,
        name: name,
      );
    }
    return _TypedScalarFlipFlop<LogicType>(
      clk,
      d,
      outputSchema,
      en: en,
      reset: reset,
      resetValue: resetValue,
      asyncReset: asyncReset,
      name: name,
    );
  }

  FlipFlop._({super.name, super.definitionName});

  /// Constructs a scalar sequential flip-flop for subclass implementations.
  ///
  /// The public unnamed constructor should be preferred for normal use. This
  /// constructor preserves the historical subclassing seam for a custom
  /// scalar flip-flop; it must be instantiated as [FlipFlop]<[Logic]>.
  FlipFlop.scalar(
    Logic clk,
    Logic d, {
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    bool asyncReset = false,
    super.name = 'flipflop',
  }) : super() {
    if (LogicType != Logic) {
      throw LogicConstructionException(
        'FlipFlop.scalar is only valid for FlipFlop<Logic>.',
      );
    }
    if (clk.width != 1) {
      throw PortWidthMismatchException(clk, 1);
    }
    if (en != null && en.width != 1) {
      throw PortWidthMismatchException(en, 1);
    }
    if (reset != null && reset.width != 1) {
      throw PortWidthMismatchException(reset, 1);
    }
    if (resetValue is Logic && resetValue.width != d.width) {
      throw PortWidthMismatchException.equalWidth(resetValue, d);
    }

    _scalarAsyncReset = asyncReset;
    final localClock = addInput('clk', clk);
    final localD = addInput('d', d, width: d.width);
    final localEnable = en == null ? null : addInput('en', en);
    final localReset = reset == null ? null : addInput('reset', reset);
    final localResetValue = reset != null && resetValue is Logic
        ? addInput('resetValue', resetValue, width: d.width)
        : null;
    _scalarConstantResetValue = reset == null || resetValue is Logic
        ? null
        : LogicValue.of(resetValue ?? 0, width: d.width);
    _scalarQ = addOutput('q', width: d.width) as LogicType;

    var contents = [_scalarQ < localD];
    if (localEnable case final enable?) {
      contents = [If(enable, then: contents)];
    }
    Sequential(
      localClock,
      contents,
      reset: localReset,
      asyncReset: asyncReset,
      resetValues: localReset == null
          ? null
          : {_scalarQ: localResetValue ?? _scalarConstantResetValue!},
    );
  }
}

/// Scalar SystemVerilog implementation of [FlipFlop].
class _ScalarFlipFlop extends FlipFlop<Logic> with SystemVerilog {
  final String _enName = Naming.unpreferredName('en');
  final String _clkName = Naming.unpreferredName('clk');
  final String _dName = Naming.unpreferredName('d');
  final String _qName = Naming.unpreferredName('q');
  final String _resetName = Naming.unpreferredName('reset');
  final String _resetValueName = Naming.unpreferredName('resetValue');

  late final Logic _clk = input(_clkName);
  late final Logic? _en = tryInput(_enName);
  late final Logic? _reset = tryInput(_resetName);
  late final Logic _d = input(_dName);

  @override
  late final Logic q;

  Logic? _resetValuePort;
  late LogicValue _resetValueConst;

  @override
  final bool asyncReset;

  @override
  LogicValue? get constantResetValue =>
      _reset == null || _resetValuePort != null ? null : _resetValueConst;

  _ScalarFlipFlop(
    Logic clk,
    Logic d,
    Logic outputSchema, {
    required this.asyncReset,
    required bool usesOutputGenerator,
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    super.name = 'flipflop',
  }) : super._() {
    addInput(_clkName, clk);
    addInput(_dName, d, width: d.width);
    q = usesOutputGenerator
        ? addTypedOutput(
            _qName,
            operationOutputClone(outputSchema),
          )
        : addOutput(
            _qName,
            width: d.width,
          );

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

  void _setup() {
    var contents = [q < _d];
    if (_en case final en?) {
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
    ].map((value) => 'posedge $value').join(' or ');

    final svBuffer = StringBuffer('always_ff @($triggerString) ');
    if (reset != null) {
      final resetValueString = _resetValuePort != null
          ? ports[_resetValueName]!
          : _resetValueConst.toString();
      svBuffer.write('if($reset) $q <= $resetValueString; else ');
    }
    if (en != null) {
      svBuffer.write('if($en) ');
    }
    svBuffer.write('$q <= $d;  // $instanceName');
    return svBuffer.toString();
  }
}

String _structuredFlipFlopResetIdentity(
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

String _structuredFlipFlopDefinitionName(
  LogicStructure structure, {
  required bool hasEnable,
  required bool hasReset,
  required bool hasResetPort,
  required dynamic resetValue,
  required bool asyncReset,
}) =>
    'FlipFlop_${logicStructureShapeSignature(structure)}_'
    '${hasEnable ? 'E' : 'N'}_'
    '${_structuredFlipFlopResetIdentity(
      structure,
      hasReset,
      hasResetPort,
      resetValue,
    )}_'
    '${asyncReset ? 'A' : 'S'}';

/// Structure-preserving implementation of [FlipFlop].
class _StructuredFlipFlop<LogicType extends Logic> extends FlipFlop<LogicType> {
  @override
  late final LogicType q;

  @override
  final bool asyncReset;

  @override
  final LogicValue? constantResetValue;

  _StructuredFlipFlop(
    Logic clk,
    LogicType d,
    LogicType outputSchema, {
    required this.asyncReset,
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    super.name = 'flipflop',
  })  : constantResetValue = reset != null && resetValue is! Logic
            ? LogicValue.of(resetValue ?? 0, width: d.width)
            : null,
        super._(
          definitionName: _structuredFlipFlopDefinitionName(
            outputSchema as LogicStructure,
            hasEnable: en != null,
            hasReset: reset != null,
            hasResetPort: reset != null && resetValue is Logic,
            resetValue: resetValue,
            asyncReset: asyncReset,
          ),
        ) {
    final localClock = addInput('clk', clk);
    final localD = addTypedInput('d', d);
    final localEnable = en == null ? null : addInput('en', en);
    final localReset = reset == null ? null : addInput('reset', reset);
    final localResetValue = reset != null && resetValue is Logic
        ? addInput('resetValue', resetValue, width: d.width)
        : null;
    q = addTypedOutput(
      'q',
      operationOutputClone(outputSchema),
    );

    final structuredQ = q as LogicStructure;
    final structuredD = localD as LogicStructure;
    var offset = 0;
    for (var index = 0; index < structuredQ.leafElements.length; index++) {
      final leaf = structuredQ.leafElements[index];
      final width = leaf.width;
      final leafResetValue = localResetValue != null
          ? localResetValue.getRange(offset, offset + width)
          : constantResetValue?.getRange(offset, offset + width);
      leaf <=
          flop<Logic>(
            localClock,
            structuredD.leafElements[index],
            en: localEnable,
            reset: localReset,
            resetValue: leafResetValue,
            asyncReset: asyncReset,
          );
      offset += width;
    }
  }
}

/// Generic scalar-subclass implementation of [FlipFlop].
///
/// This path supports scalar domain types such as future `LogicEnum` signals.
class _TypedScalarFlipFlop<LogicType extends Logic>
    extends FlipFlop<LogicType> {
  @override
  late final LogicType q;

  @override
  final bool asyncReset;

  @override
  LogicValue? get constantResetValue => null;

  _TypedScalarFlipFlop(
    Logic clk,
    LogicType d,
    LogicType outputSchema, {
    required this.asyncReset,
    Logic? en,
    Logic? reset,
    dynamic resetValue,
    super.name = 'flipflop',
  }) : super._(
          definitionName:
              'FlipFlop_${outputSchema.runtimeType}_W${outputSchema.width}',
        ) {
    final localClock = addInput('clk', clk);
    final localD = addTypedInput('d', d);
    final localEnable = en == null ? null : addInput('en', en);
    final localReset = reset == null ? null : addInput('reset', reset);
    final localResetValue = reset != null && resetValue is Logic
        ? addInput('resetValue', resetValue, width: d.width)
        : resetValue;
    q = addTypedOutput(
      'q',
      operationOutputClone(outputSchema),
    );

    var contents = [q < localD];
    if (localEnable case final enable?) {
      contents = [If(enable, then: contents)];
    }
    Sequential(
      localClock,
      contents,
      reset: localReset,
      asyncReset: asyncReset,
      resetValues: localReset == null ? null : {q: localResetValue ?? 0},
    );
  }
}

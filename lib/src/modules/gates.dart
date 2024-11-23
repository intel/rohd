// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// gates.dart
// Definition for basic gates
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A gate [Module] that performs bit-wise inversion.
class NotGate extends Module with InlineSystemVerilog {
  /// Name for the input of this inverter.
  late final String _inName;

  /// Name for the output of this inverter.
  late final String _outName;

  /// The input to this [NotGate].
  late final Logic _in = input(_inName);

  /// The output of this [NotGate].
  late final Logic out = output(_outName);

  /// Constructs a [NotGate] with [in_] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic in_, {super.name = 'not'}) {
    _inName = Naming.unpreferredName(in_.name);
    _outName = Naming.unpreferredName('${in_.name}_b');
    addInput(_inName, in_, width: in_.width);
    addOutput(_outName, width: in_.width)
        .makeUnassignable(reason: 'Output of a gate $this cannot be assigned.');
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(~_in.value);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    assert(inputs.length == 1, 'Gate has exactly one input.');

    final a = inputs[_inName]!;
    return '~$a';
  }
}

/// A generic unary gate [Module].
///
/// It always takes one input, and the output width is always 1.
class _OneInputUnaryGate extends Module with InlineSystemVerilog {
  /// Name for the input port of this module.
  late final String _inName;

  /// Name for the output port of this module.
  late final String _outName;

  /// The input to this gate.
  late final Logic _in = input(_inName);

  /// The output of this gate (width is always 1).
  late final Logic out = output(_outName);

  /// The output of this gate (width is always 1).
  ///
  /// Deprecated: use [out] instead.
  @Deprecated('Use `out` instead.')
  Logic get y => out;

  final LogicValue Function(LogicValue a) _op;
  final String _opStr;

  /// Constructs a unary gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as the
  /// prefix to the input signal name (e.g. if [_opStr] was "&", generated
  /// SystemVerilog may look like "&a").
  _OneInputUnaryGate(this._op, this._opStr, Logic in_, {String name = 'ugate'})
      : super(name: name) {
    _inName = Naming.unpreferredName(in_.name);
    _outName = Naming.unpreferredName('${name}_${in_.name}');
    addInput(_inName, in_, width: in_.width);
    addOutput(_outName)
        .makeUnassignable(reason: 'Output of a gate $this cannot be assigned.');
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }
    final in_ = inputs[_inName]!;
    return '$_opStr$in_';
  }
}

/// A generic two-input bitwise gate [Module].
///
/// It always takes two inputs and has one output.  All ports have the
/// same width.
abstract class _TwoInputBitwiseGate extends Module with InlineSystemVerilog {
  /// Name for a first input port of this module.
  late final String _in0Name;

  /// Name for a second input port of this module.
  late final String _in1Name;

  /// Name for the output port of this module.
  late final String _outName;

  /// An input to this gate.
  late final Logic _in0 = input(_in0Name);

  /// An input to this gate.
  late final Logic _in1 = input(_in1Name);

  /// The output of this gate.
  late final Logic out = _outputSvWidthExpansion != 0
      // this is sub-optimal, but it's tricky to make special SV for it
      ? BusSubset(output(_outName), 0, width - _outputSvWidthExpansion).subset
      : output(_outName);

  /// The output of this gate.
  ///
  /// Deprecated: use [out] instead.
  @Deprecated('Use `out` instead.')
  Logic get y => out;

  /// The functional operation to perform for this gate.
  final LogicValue Function(LogicValue in0, LogicValue in1) _op;

  /// The `String` representing the operation to perform in generated code.
  final String _opStr;

  /// The width of the inputs and outputs for this operation.
  final int width;

  /// If non-zero, then the output generated SystemVerilog may have a larger
  /// width than the inputs, which should be considered in generated verilog.
  final int _outputSvWidthExpansion;

  /// If true, it will wrap the expression in `{}` to try to force the
  /// expression to behave as a self-determined width.
  final bool _makeSelfDetermined;

  /// Constructs a two-input bitwise gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was "&",
  /// generated SystemVerilog may look like "a & b").
  _TwoInputBitwiseGate(this._op, this._opStr, Logic in0, dynamic in1,
      {String name = 'gate2',
      int outputSvWidthExpansion = 0,
      bool makeSelfDetermined = false})
      : width = in0.width,
        assert(!outputSvWidthExpansion.isNegative, 'Should not be negative.'),
        _outputSvWidthExpansion = outputSvWidthExpansion,
        _makeSelfDetermined = makeSelfDetermined,
        super(name: name) {
    if (in1 is Logic && in0.width != in1.width) {
      throw PortWidthMismatchException.equalWidth(in0, in1);
    }

    final in1Logic = in1 is Logic ? in1 : Const(in1, width: width);

    _in0Name = Naming.unpreferredName('in0_${in0.name}');
    _in1Name = Naming.unpreferredName('in1_${in1Logic.name}');
    _outName = Naming.unpreferredName('${in0.name}_${name}_${in1Logic.name}');

    addInput(_in0Name, in0, width: width);
    addInput(_in1Name, in1Logic, width: width);
    addOutput(_outName, width: width + _outputSvWidthExpansion)
        .makeUnassignable(reason: 'Output of a gate $this cannot be assigned.');

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in0.glitch.listen((args) {
      _execute();
    });
    _in1.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in0.value, _in1.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final in0 = inputs[_in0Name]!;
    final in1 = inputs[_in1Name]!;
    var sv = '$in0 $_opStr $in1';
    if (_makeSelfDetermined) {
      sv = '{$sv}';
    }
    return sv;
  }
}

/// A generic two-input comparison gate [Module].
///
/// It always takes two inputs of the same width and has one 1-bit output.
abstract class _TwoInputComparisonGate extends Module with InlineSystemVerilog {
  /// Name for a first input port of this module.
  late final String _in0Name;

  /// Name for a second input port of this module.
  late final String _in1Name;

  /// Name for the output port of this module.
  late final String _outName;

  /// An input to this gate.
  late final Logic _in0 = input(_in0Name);

  /// An input to this gate.
  late final Logic _in1 = input(_in1Name);

  /// The output of this gate.
  late final Logic out = output(_outName);

  /// The output of this gate.
  ///
  /// Deprecated: use [out] instead.
  @Deprecated('Use `out` instead.')
  Logic get y => out;

  /// The functional operation to perform for this gate.
  final LogicValue Function(LogicValue in0, LogicValue in1) _op;

  /// The `String` representing the operation to perform in generated code.
  final String _opStr;

  /// Constructs a two-input comparison gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was ">",
  /// generated SystemVerilog may look like "a > b").
  _TwoInputComparisonGate(this._op, this._opStr, Logic in0, dynamic in1,
      {String name = 'cmp2'})
      : super(name: name) {
    if (in1 is Logic && in0.width != in1.width) {
      throw Exception('Input widths must match,'
          ' but found $in0 and $in1 with different widths.');
    }

    final in1Logic = in1 is Logic ? in1 : Const(in1, width: in0.width);

    _in0Name = Naming.unpreferredName('in0_${in0.name}');
    _in1Name = Naming.unpreferredName('in1_${in1Logic.name}');
    _outName = Naming.unpreferredName('${in0.name}_${name}_${in1Logic.name}');

    addInput(_in0Name, in0, width: in0.width);
    addInput(_in1Name, in1Logic, width: in1Logic.width);
    addOutput(_outName)
        .makeUnassignable(reason: 'Output of a gate $this cannot be assigned.');

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in0.glitch.listen((args) {
      _execute();
    });
    _in1.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in0.value, _in1.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final in0 = inputs[_in0Name]!;
    final in1 = inputs[_in1Name]!;
    return '$in0 $_opStr $in1';
  }
}

/// A generic two-input shift gate [Module].
///
/// It always takes two inputs and has one output of equal width to the primary
/// of the input.
abstract class _ShiftGate extends Module with InlineSystemVerilog {
  /// Name for the main input port of this module.
  late final String _inName;

  /// Name for the shift amount input port of this module.
  late String _shiftAmountName;

  /// Name for the output port of this module.
  late final String _outName;

  @override
  String get resultSignalName => _outName;

  /// The primary input to this gate.
  late final Logic _in;

  /// The shift amount for this gate.
  late final Logic _shiftAmount;

  /// The output of this gate.
  late final Logic out;

  /// The functional operation to perform for this gate.
  final LogicValue Function(LogicValue in_, LogicValue shiftAmount) _op;

  /// The `String` representing the operation to perform in generated code.
  final String _opStr;

  /// Whether or not this gate operates on a signed number.
  final bool signed;

  /// The width of the output for this operation.
  final int width;

  /// If true, then the output generated SystemVerilog may have a larger width
  /// than the inputs, which should be considered in generated verilog.
  final bool _outputSvWidthExpansion;

  @override
  List<String> get expressionlessInputs => [
        if (_outputSvWidthExpansion) _shiftAmountName,
      ];

  /// Indicates whether this operates on nets, supporting bidirectionality.
  final bool _isNet;

  /// If the shift amount is a constant, this will be set to that constant.
  late final LogicValue? _shiftAmountConstant;

  /// Constructs a two-input shift gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was ">>",
  /// generated SystemVerilog may look like "a >> b").
  _ShiftGate(this._op, this._opStr, Logic in_, dynamic shiftAmount,
      {String name = 'gate2',
      this.signed = false,
      bool outputSvWidthExpansion = false})
      : width = in_.width,
        _outputSvWidthExpansion = outputSvWidthExpansion,
        _isNet = in_.isNet &&
            // if it's a Logic, then we can't treat this like a net
            shiftAmount is! Logic,
        super(name: name) {
    final Logic shiftAmountLogic;
    if (shiftAmount is Const) {
      shiftAmountLogic = shiftAmount;
      _shiftAmountConstant = shiftAmount.value;
    } else if (shiftAmount is Logic) {
      shiftAmountLogic = shiftAmount;
      _shiftAmountConstant = null;
    } else {
      if (_outputSvWidthExpansion) {
        _shiftAmountConstant = LogicValue.of(shiftAmount, width: width);
        shiftAmountLogic = Const(_shiftAmountConstant);
      } else {
        _shiftAmountConstant = LogicValue.ofInferWidth(shiftAmount);
        if (_shiftAmountConstant!.isZero) {
          shiftAmountLogic = Const(_shiftAmountConstant, width: 1);
        } else {
          shiftAmountLogic = Const(_shiftAmountConstant);
        }
      }
    }

    _inName = Naming.unpreferredName('in_${in_.name}');

    _shiftAmountName =
        Naming.unpreferredName('shiftAmount_${shiftAmountLogic.name}');

    _outName =
        Naming.unpreferredName('${in_.name}_${name}_${shiftAmountLogic.name}');

    final inputCreator = _isNet ? addInOut : addInput;

    _in = inputCreator(_inName, in_, width: in_.width);
    _shiftAmount = inputCreator(_shiftAmountName, shiftAmountLogic,
        width: shiftAmountLogic.width);

    if (_isNet) {
      out = LogicNet(name: _outName, width: width, naming: Naming.unnamed);
      final internalOut = addInOut(_outName, out, width: width);

      _netSetup(internalOut);
    } else {
      out = addOutput(_outName, width: width)
        ..makeUnassignable(
            reason: 'Output of a gate $this cannot be assigned.');

      _setup();
    }
  }

  /// A setup function for net functionality.
  void _netSetup(LogicNet internalOut);

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
    _shiftAmount.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in.value, _shiftAmount.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final in_ = inputs[_inName]!;
    final shiftAmount = inputs[_shiftAmountName]!;

    String signWrap(String original) =>
        signed ? '\$signed($original)' : original;

    final aStr = signWrap(in_);

    final shiftStr = '$aStr $_opStr $shiftAmount';

    // In case of signed, wrap in {} to make it self-determined.
    return signed ? '{$shiftStr}' : shiftStr;
  }
}

/// A two-input AND gate.
class And2Gate extends _TwoInputBitwiseGate {
  /// Calculates the AND of [in0] and [in1].
  And2Gate(Logic in0, Logic in1, {String name = 'and'})
      : super((a, b) => a & b, '&', in0, in1, name: name);
}

/// A two-input OR gate.
class Or2Gate extends _TwoInputBitwiseGate {
  /// Calculates the OR of [in0] and [in1].
  Or2Gate(Logic in0, Logic in1, {String name = 'or'})
      : super((a, b) => a | b, '|', in0, in1, name: name);
}

/// A two-input XOR gate.
class Xor2Gate extends _TwoInputBitwiseGate {
  /// Calculates the XOR of [in0] and [in1].
  Xor2Gate(Logic in0, Logic in1, {String name = 'xor'})
      : super((a, b) => a ^ b, '^', in0, in1, name: name);
}

/// A two-input power module.
class Power extends _TwoInputBitwiseGate {
  /// Calculates [in0] raise to power of [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Power(Logic in0, dynamic in1, {String name = 'power'})
      : super((a, b) => a.pow(b), '**', in0, in1,
            name: name, makeSelfDetermined: true);
}

/// A two-input addition module.
class Add extends _TwoInputBitwiseGate {
  /// Calculates the sum of [in0] and [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Add(Logic in0, dynamic in1, {String name = 'add'})
      : super((a, b) => a + b, '+', in0, in1,
            name: name, outputSvWidthExpansion: 1);
}

/// A two-input subtraction module.
class Subtract extends _TwoInputBitwiseGate {
  /// Calculates the difference between [in0] and [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Subtract(Logic in0, dynamic in1, {String name = 'subtract'})
      : super((a, b) => a - b, '-', in0, in1, name: name);
}

/// A two-input multiplication module.
class Multiply extends _TwoInputBitwiseGate {
  /// Calculates the product of [in0] and [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Multiply(Logic in0, dynamic in1, {String name = 'multiply'})
      : super((a, b) => a * b, '*', in0, in1,
            name: name, makeSelfDetermined: true);
}

/// A two-input divison module.
class Divide extends _TwoInputBitwiseGate {
  /// Calculates [in0] divided by [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Divide(Logic in0, dynamic in1, {String name = 'divide'})
      : super((a, b) => a / b, '/', in0, in1, name: name);
}

/// A two-input modulo module.
class Modulo extends _TwoInputBitwiseGate {
  /// Calculates the module of [in0] % [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Modulo(Logic in0, dynamic in1, {String name = 'modulo'})
      : super((a, b) => a % b, '%', in0, in1, name: name);
}

/// A two-input equality comparison module.
class Equals extends _TwoInputComparisonGate {
  /// Calculates whether [in0] and [in1] are equal.
  ///
  /// [in1] can be either a [Logic] or [int].
  Equals(Logic in0, dynamic in1, {String name = 'equals'})
      : super((a, b) => a.eq(b), '==', in0, in1, name: name);
}

/// A two-input inequality comparison module.
class NotEquals extends _TwoInputComparisonGate {
  /// Calculates whether [in0] and [in1] are not-equal.
  ///
  /// [in1] can be either a [Logic] or [int].
  NotEquals(Logic in0, dynamic in1, {String name = 'notEquals'})
      : super((a, b) => a.neq(b), '!=', in0, in1, name: name);
}

/// A two-input comparison module for less-than.
class LessThan extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is less than [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  LessThan(Logic in0, dynamic in1, {String name = 'lessthan'})
      : super((a, b) => a < b, '<', in0, in1, name: name);
}

/// A two-input comparison module for greater-than.
class GreaterThan extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is greater than [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  GreaterThan(Logic in0, dynamic in1, {String name = 'greaterThan'})
      : super((a, b) => a > b, '>', in0, in1, name: name);
}

/// A two-input comparison module for less-than-or-equal-to.
class LessThanOrEqual extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is less than or equal to [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  LessThanOrEqual(Logic in0, dynamic in1, {String name = 'lessThanOrEqual'})
      : super((a, b) => a <= b, '<=', in0, in1, name: name);
}

/// A two-input comparison module for greater-than-or-equal-to.
class GreaterThanOrEqual extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is greater than or equal to [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  GreaterThanOrEqual(Logic in0, dynamic in1,
      {String name = 'greaterThanOrEqual'})
      : super((a, b) => a >= b, '>=', in0, in1, name: name);
}

/// A unary AND gate.
class AndUnary extends _OneInputUnaryGate {
  /// Calculates whether all bits of [in_] are high.
  AndUnary(Logic in_, {String name = 'uand'})
      : super((a) => a.and(), '&', in_, name: name);
}

/// A unary OR gate.
class OrUnary extends _OneInputUnaryGate {
  /// Calculates whether any bits of [in_] are high.
  OrUnary(Logic in_, {String name = 'uor'})
      : super((a) => a.or(), '|', in_, name: name);
}

/// A unary XOR gate.
class XorUnary extends _OneInputUnaryGate {
  /// Calculates the parity of the bits of [in_].
  XorUnary(Logic in_, {String name = 'uxor'})
      : super((a) => a.xor(), '^', in_, name: name);
}

/// A logical right-shift module.
///
/// Note that many simulators do not support the SystemVerilog generated by this
/// module when it operates on [LogicNet]s. The default shift operators on
/// [Logic] will instead use swizzling to accomplish equivalent behavior.
class RShift extends _ShiftGate {
  /// Calculates the value of [in_] shifted right (logically) by [shiftAmount].
  RShift(Logic in_, dynamic shiftAmount, {String name = 'rshift'})
      : // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >>> shamt, '>>', in_, shiftAmount, name: name);

  @override
  void _netSetup(LogicNet internalOut) {
    internalOut <= (_in >>> _shiftAmountConstant);
  }
}

/// An arithmetic right-shift module.
///
/// Note that many simulators do not support the SystemVerilog generated by this
/// module when it operates on [LogicNet]s. The default shift operators on
/// [Logic] will instead use swizzling to accomplish equivalent behavior.
class ARShift extends _ShiftGate {
  /// Calculates the value of [in_] shifted right (arithmetically) by
  /// [shiftAmount].
  ARShift(Logic in_, dynamic shiftAmount, {String name = 'arshift'})
      : // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >> shamt, '>>>', in_, shiftAmount,
            name: name, signed: true);

  @override
  void _netSetup(LogicNet internalOut) {
    internalOut <= (_in >> _shiftAmountConstant);
  }
}

/// A logical left-shift module.
///
/// Note that many simulators do not support the SystemVerilog generated by this
/// module when it operates on [LogicNet]s. The default shift operators on
/// [Logic] will instead use swizzling to accomplish equivalent behavior.
class LShift extends _ShiftGate {
  /// Calculates the value of [in_] shifted left by [shiftAmount].
  LShift(Logic in_, dynamic shiftAmount, {String name = 'lshift'})
      : super((a, shamt) => a << shamt, '<<', in_, shiftAmount,
            name: name, outputSvWidthExpansion: true);

  @override
  void _netSetup(LogicNet internalOut) {
    internalOut <= (_in << _shiftAmountConstant);
  }
}

/// Performs a multiplexer/ternary operation.
///
/// This is equivalent to something like:
/// ```SystemVerilog
/// control ? d1 : d0
/// ```
Logic mux(Logic control, Logic d1, Logic d0) => Mux(control, d1, d0).out;

/// A mux (multiplexer) module.
///
/// If [_control] has value `1`, then [out] gets [_d1].
/// If [_control] has value `0`, then [out] gets [_d0].
class Mux extends Module with InlineSystemVerilog {
  /// Name for the control signal of this mux.
  late final String _controlName;

  /// Name for the input selected when control is 0.
  late final String _d0Name;

  /// Name for the input selected when control is 1.
  late final String _d1Name;

  /// Name for the output port of this mux.
  late final String _outName;

  /// The control signal for this [Mux].
  late final Logic _control = input(_controlName);

  /// [Mux] input propogated when [out] is `0`.
  late final Logic _d0 = input(_d0Name);

  /// [Mux] input propogated when [out] is `1`.
  late final Logic _d1 = input(_d1Name);

  /// Output port of the [Mux].
  late final Logic out = output(_outName);

  /// Output port of the [Mux].
  ///
  /// Use [out] or  [mux] instead.
  @Deprecated('Use `out` or `mux` instead.')
  Logic get y => out;

  /// Constructs a multiplexer which passes [d0] or [d1] to [out] depending
  /// on if [control] is 0 or 1, respectively.
  Mux(Logic control, Logic d1, Logic d0, {super.name = 'mux'}) {
    if (control.width != 1) {
      throw PortWidthMismatchException(control, 1);
    }
    if (d0.width != d1.width) {
      throw PortWidthMismatchException.equalWidth(d0, d1);
    }

    _controlName = Naming.unpreferredName('control_${control.name}');
    _d0Name = Naming.unpreferredName('d0_${d0.name}');
    _d1Name = Naming.unpreferredName('d1_${d1.name}');
    _outName = Naming.unpreferredName('out');

    addInput(_controlName, control);
    addInput(_d0Name, d0, width: d0.width);
    addInput(_d1Name, d1, width: d1.width);
    addOutput(_outName, width: d0.width)
        .makeUnassignable(reason: 'Output of a gate $this cannot be assigned.');

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values

    _d0.glitch.listen((args) {
      _execute();
    });
    _d1.glitch.listen((args) {
      _execute();
    });
    _control.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of the mux.
  void _execute() {
    if (!_control.value.isValid) {
      out.put(LogicValue.x);
    } else if (_control.value == LogicValue.zero) {
      out.put(_d0.value.isValid ? _d0.value : LogicValue.x);
    } else if (_control.value == LogicValue.one) {
      out.put(_d1.value.isValid ? _d1.value : LogicValue.x);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 3) {
      throw Exception('Mux2 has exactly three inputs.');
    }
    final d0 = inputs[_d0Name]!;
    final d1 = inputs[_d1Name]!;
    final control = inputs[_controlName]!;
    return '$control ? $d1 : $d0';
  }
}

/// A two-input bit index gate [Module].
///
/// It always takes two inputs and has one output of width 1.
class IndexGate extends Module with InlineSystemVerilog {
  late final String _originalName;
  late final String _indexName;
  late final String _selectionName;

  /// The primary input to this gate.
  late final Logic _original = input(_originalName);

  /// The bit index for this gate.
  late final Logic _index = input(_indexName);

  /// The output of this gate.
  late final Logic selection = output(_selectionName);

  /// Constructs a two-input bit index gate for an abitrary custom functional
  /// implementation.
  ///
  /// The signal will be indexed by [index] as an output.
  /// [Module] is in-lined as SystemVerilog, it will use original[index], where
  /// target is index's int value
  /// When, the [original] has width '1', [index] is ignored in the generated
  /// SystemVerilog.
  IndexGate(Logic original, Logic index) : super() {
    _originalName = 'original_${original.name}';
    _indexName = Naming.unpreferredName('index_${index.name}');
    _selectionName =
        Naming.unpreferredName('${original.name}_indexby_${index.name}');

    addInput(_originalName, original, width: original.width);
    addInput(_indexName, index, width: index.width);
    addOutput(_selectionName)
        .makeUnassignable(reason: 'Output of a gate $this cannot be assigned.');

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _original.glitch.listen((args) {
      _execute();
    });
    _index.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    if (_index.value.isValid && _index.value.toInt() < _original.width) {
      final indexVal = _index.value.toInt();
      final outputValue = _original.value.getRange(indexVal, indexVal + 1);
      selection.put(outputValue);
    } else {
      selection.put(LogicValue.x);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }

    final target = inputs[_originalName]!;

    if (_original.width == 1) {
      return target;
    }

    final idx = inputs[_indexName]!;
    return '$target[$idx]';
  }
}

/// A Replication Operator [Module].
///
/// It takes two inputs (original and multiplier) and outputs a [Logic]
/// representing the input repeated over the multiple.
///
/// Note that many simulators do not support the SystemVerilog generated by this
/// module when it operates on [LogicNet]s. The default [Logic.replicate]
/// function will instead use swizzling to accomplish equivalent behavior.
class ReplicationOp extends Module with InlineSystemVerilog {
  /// Input name.
  final String _inputName;

  /// Output name.
  final String _outputName;

  /// Number of times to replicate the input in the output.
  final int _multiplier;

  /// The primary input to this gate.
  late final Logic _input = input(_inputName);

  /// The output of this gate.
  late final Logic replicated;

  /// Indicates whether this operates on nets, supporting bidirectionality.
  final bool _isNet;

  /// Constructs a ReplicationOp
  ///
  /// The signal [original] will be repeated over the [_multiplier] times as an
  /// output.
  /// Input [_multiplier] cannot be negative or zero, an exception will be
  /// thrown, otherwise.
  /// [Module] is in-lined as SystemVerilog, it will use {width{bit}}
  ReplicationOp(Logic original, this._multiplier)
      : _inputName = Naming.unpreferredName(original.name),
        _outputName = Naming.unpreferredName('replicated_${original.name}'),
        _isNet = original.isNet {
    final newWidth = original.width * _multiplier;
    if (newWidth < 1) {
      throw InvalidMultiplierException(newWidth);
    }

    if (_isNet) {
      original = addInOut(_inputName, original, width: original.width);

      replicated =
          LogicNet(name: _outputName, width: newWidth, naming: Naming.unnamed);
      final internalOut = addInOut(_outputName, replicated, width: newWidth);

      for (var i = 0; i < _multiplier; i++) {
        internalOut.quietlyMergeSubsetTo(original as LogicNet,
            start: i * original.width);
      }
    } else {
      addInput(_inputName, original, width: original.width);
      replicated = addOutput(_outputName, width: original.width * _multiplier)
        ..makeUnassignable(
            reason: 'Output of a gate $this cannot be assigned.');
      _setup();
    }
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _input.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    replicated.put(_input.value.replicate(_multiplier));
  }

  @override
  String get resultSignalName => _outputName;

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }

    final target = inputs[_inputName]!;
    final width = _multiplier;
    return '{$width{$target}}';
  }
}

/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// gates.dart
/// Definition for basic gates
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// A gate [Module] that performs bit-wise inversion.
class NotGate extends Module with InlineSystemVerilog {
  /// Name for a port of this module.
  late final String _a, _out;

  /// The input to this [NotGate].
  Logic get a => input(_a);

  /// The output of this [NotGate].
  Logic get out => output(_out);

  /// Constructs a [NotGate] with [a] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic a, {String name = 'not'}) : super(name: name) {
    _a = Module.unpreferredName(a.name);
    _out = Module.unpreferredName('${a.name}_b');
    addInput(_a, a, width: a.width);
    addOutput(_out, width: a.width);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(~a.value);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) throw Exception('Gate has exactly one input.');
    var a = inputs[_a]!;
    return '~$a';
  }
}

/// A generic unary gate [Module].
///
/// It always takes one input, and the output width is always 1.
class _OneInputUnaryGate extends Module with InlineSystemVerilog {
  /// Name for a port of this module.
  late final String _a, _y;

  /// The input to this gate.
  Logic get a => input(_a);

  /// The output of this gate (width is always 1).
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a) _op;
  final String _opStr;

  /// Constructs a unary gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_opStr] as the prefix to the
  /// input signal name (e.g. if [_opStr] was "&", generated SystemVerilog may look like "&a").
  _OneInputUnaryGate(this._op, this._opStr, Logic a, {String name = 'ugate'})
      : super(name: name) {
    _a = Module.unpreferredName(a.name);
    _y = Module.unpreferredName(name + '_' + a.name);
    addInput(_a, a, width: a.width);
    addOutput(_y);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    y.put(_op(a.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) throw Exception('Gate has exactly one input.');
    var a = inputs[_a]!;
    return '$_opStr$a';
  }
}

/// A generic two-input bitwise gate [Module].
///
/// It always takes two inputs and has one output.  All ports have the same width.
abstract class _TwoInputBitwiseGate extends Module with InlineSystemVerilog {
  /// Name for a port of this module.
  late final String _a, _b, _y;

  /// An input to this gate.
  Logic get a => input(_a);

  /// An input to this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a, LogicValue b) _op;
  final String _opStr;

  /// Constructs a two-input bitwise gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_opStr] as a String between the two input
  /// signal names (e.g. if [_opStr] was "&", generated SystemVerilog may look like "a & b").
  _TwoInputBitwiseGate(this._op, this._opStr, Logic a, dynamic b,
      {String name = 'gate2'})
      : super(name: name) {
    if (b is Logic && a.width != b.width) {
      throw Exception(
          'Input widths must match, but found $a and $b with different widths.');
    }

    var bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_' + a.name);
    _b = Module.unpreferredName('b_' + bLogic.name);
    _y = Module.unpreferredName('${a.name}_${name}_${bLogic.name}');

    addInput(_a, a, width: a.width);
    addInput(_b, bLogic, width: bLogic.width);
    addOutput(_y, width: a.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
    b.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    dynamic toPut;
    try {
      toPut = _op(a.value, b.value);
    } catch (e) {
      // in case of things like divide by 0
      toPut = LogicValue.x;
    }
    y.put(toPut);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    var a = inputs[_a]!;
    var b = inputs[_b]!;
    return '$a $_opStr $b';
  }
}

/// A generic two-input comparison gate [Module].
///
/// It always takes two inputs of the same width and has one 1-bit output.
abstract class _TwoInputComparisonGate extends Module with InlineSystemVerilog {
  late final String _a, _b, _y;

  /// An input to this gate.
  Logic get a => input(_a);

  /// An input to this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a, LogicValue b) _op;
  final String _opStr;

  /// Constructs a two-input comparison gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_opStr] as a String between the two input
  /// signal names (e.g. if [_opStr] was ">", generated SystemVerilog may look like "a > b").
  _TwoInputComparisonGate(this._op, this._opStr, Logic a, dynamic b,
      {String name = 'cmp2'})
      : super(name: name) {
    if (b is Logic && a.width != b.width) {
      throw Exception(
          'Input widths must match, but found $a and $b with different widths.');
    }

    var bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_' + a.name);
    _b = Module.unpreferredName('b_' + bLogic.name);
    _y = Module.unpreferredName('${a.name}_${name}_${bLogic.name}');

    addInput(_a, a, width: a.width);
    addInput(_b, bLogic, width: bLogic.width);
    addOutput(_y);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
    b.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    y.put(_op(a.value, b.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    var a = inputs[_a]!;
    var b = inputs[_b]!;
    return '$a $_opStr $b';
  }
}

/// A generic two-input shift gate [Module].
///
/// It always takes two inputs and has one output of equal width to the primary of the input.
class _ShiftGate extends Module with InlineSystemVerilog {
  late final String _a, _b, _y;

  /// The primary input to this gate.
  Logic get a => input(_a);

  /// The shift amount for this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a, LogicValue b) _op;
  final String _opStr;

  /// Whether or not this gate operates on a signed number.
  final bool signed;

  /// Constructs a two-input shift gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_opStr] as a String between the two input
  /// signal names (e.g. if [_opStr] was ">>", generated SystemVerilog may look like "a >> b").
  _ShiftGate(this._op, this._opStr, Logic a, dynamic b,
      {String name = 'gate2', this.signed = false})
      : super(name: name) {
    var bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_' + a.name);
    _b = Module.unpreferredName('b_' + b.name);
    _y = Module.unpreferredName('${a.name}_${name}_${bLogic.name}');

    addInput(_a, a, width: a.width);
    addInput(_b, bLogic, width: bLogic.width);
    addOutput(_y, width: a.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
    b.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    y.put(_op(a.value, b.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    var a = inputs[_a]!;
    var b = inputs[_b]!;
    var aStr = signed ? '\$signed($a)' : a;
    return '$aStr $_opStr $b';
  }
}

/// A two-input AND gate.
class And2Gate extends _TwoInputBitwiseGate {
  And2Gate(Logic a, Logic b, {String name = 'and'})
      : super((a, b) => a & b, '&', a, b, name: name);
}

/// A two-input OR gate.
class Or2Gate extends _TwoInputBitwiseGate {
  Or2Gate(Logic a, Logic b, {String name = 'or'})
      : super((a, b) => a | b, '|', a, b, name: name);
}

/// A two-input XOR gate.
class Xor2Gate extends _TwoInputBitwiseGate {
  Xor2Gate(Logic a, Logic b, {String name = 'xor'})
      : super((a, b) => a ^ b, '^', a, b, name: name);
}

//TODO: allow math operations on different sized Logics, with optional overrideable output size

/// A two-input addition module.
class Add extends _TwoInputBitwiseGate {
  Add(Logic a, dynamic b, {String name = 'add'})
      : super((a, b) => a + b, '+', a, b, name: name);
}

/// A two-input subtraction module.
class Subtract extends _TwoInputBitwiseGate {
  Subtract(Logic a, dynamic b, {String name = 'subtract'})
      : super((a, b) => a - b, '-', a, b, name: name);
}

/// A two-input multiplication module.
class Multiply extends _TwoInputBitwiseGate {
  Multiply(Logic a, dynamic b, {String name = 'multiply'})
      : super((a, b) => a * b, '*', a, b, name: name);
}

/// A two-input divison module.
class Divide extends _TwoInputBitwiseGate {
  Divide(Logic a, dynamic b, {String name = 'divide'})
      : super((a, b) => a / b, '/', a, b, name: name);
}

/// A two-input equality comparison module.
class Equals extends _TwoInputComparisonGate {
  Equals(Logic a, dynamic b, {String name = 'equals'})
      : super((a, b) => a.eq(b), '==', a, b, name: name);
}

/// A two-input comparison module for less-than.
class LessThan extends _TwoInputComparisonGate {
  LessThan(Logic a, dynamic b, {String name = 'lessthan'})
      : super((a, b) => a < b, '<', a, b, name: name);
}

/// A two-input comparison module for greater-than.
class GreaterThan extends _TwoInputComparisonGate {
  GreaterThan(Logic a, dynamic b, {String name = 'greaterthan'})
      : super((a, b) => a > b, '>', a, b, name: name);
}

/// A two-input comparison module for less-than-or-equal-to.
class LessThanOrEqual extends _TwoInputComparisonGate {
  LessThanOrEqual(Logic a, dynamic b, {String name = 'lessthanorequal'})
      : super((a, b) => a <= b, '<=', a, b, name: name);
}

/// A two-input comparison module for greater-than-or-equal-to.
class GreaterThanOrEqual extends _TwoInputComparisonGate {
  GreaterThanOrEqual(Logic a, dynamic b, {String name = 'greaterthanorequal'})
      : super((a, b) => a >= b, '>=', a, b, name: name);
}

/// A unary AND gate.
class AndUnary extends _OneInputUnaryGate {
  AndUnary(Logic a, {String name = 'uand'})
      : super((a) => a.and(), '&', a, name: name);
}

/// A unary OR gate.
class OrUnary extends _OneInputUnaryGate {
  OrUnary(Logic a, {String name = 'uor'})
      : super((a) => a.or(), '|', a, name: name);
}

/// A unary XOR gate.
class XorUnary extends _OneInputUnaryGate {
  XorUnary(Logic a, {String name = 'uxor'})
      : super((a) => a.xor(), '^', a, name: name);
}

/// A logical right-shift module.
class RShift extends _ShiftGate {
  RShift(Logic a, Logic shamt, {String name = 'rshift'})
      :
        // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >>> shamt, '>>', a, shamt, name: name);
}

/// An arithmetic right-shift module.
class ARShift extends _ShiftGate {
  ARShift(Logic a, Logic shamt, {String name = 'arshift'})
      :
        // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >> shamt, '>>>', a, shamt,
            name: name, signed: true);
}

/// A logical left-shift module.
class LShift extends _ShiftGate {
  LShift(Logic a, Logic shamt, {String name = 'lshift'})
      : super((a, shamt) => a << shamt, '<<', a, shamt, name: name);
}

/// A mux (multiplexer) module.
///
/// If [control] has value `1`, then [y] gets [d1].
/// If [control] has value `0`, then [y] gets [d0].
class Mux extends Module with InlineSystemVerilog {
  late final String _control, _d0, _d1, _y;

  /// The control signal for this [Mux].
  Logic get control => input(_control);

  /// [Mux] input propogated when [y] is `0`.
  Logic get d0 => input(_d0);

  /// [Mux] input propogated when [y] is `1`.
  Logic get d1 => input(_d1);

  /// Output port of the [Mux].
  Logic get y => output(_y);

  Mux(Logic control, Logic d1, Logic d0, {String name = 'mux'})
      : super(name: name) {
    if (control.width != 1) {
      throw Exception('Control must be single bit Logic, but found $control.');
    }
    if (d0.width != d1.width) {
      throw Exception('d0 ($d0) and d1 ($d1) must be same width');
    }

    _control = Module.unpreferredName('control_' + control.name);
    _d0 = Module.unpreferredName('d0_' + d0.name);
    _d1 = Module.unpreferredName('d1_' + d1.name);
    _y = Module.unpreferredName('y'); //TODO: something better here?

    addInput(_control, control);
    addInput(_d0, d0, width: d0.width);
    addInput(_d1, d1, width: d1.width);
    addOutput(_y, width: d0.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values

    d0.glitch.listen((args) {
      _execute();
    });
    d1.glitch.listen((args) {
      _execute();
    });
    control.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of the mux.
  void _execute() {
    if (!control.value.isValid) {
      y.put(control.value);
    } else if (control.value == LogicValue.zero) {
      y.put(d0.value);
    } else if (control.value == LogicValue.one) {
      y.put(d1.value);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 3) throw Exception('Mux2 has exactly three inputs.');
    var d0 = inputs[_d0]!;
    var d1 = inputs[_d1]!;
    var control = inputs[_control]!;
    return '$control ? $d1 : $d0';
  }
}

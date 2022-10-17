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
  /// Name for the input of this inverter.
  late final String _a;

  /// Name for the output of this inverter.
  late final String _out;

  /// The input to this [NotGate].
  Logic get a => input(_a);

  /// The output of this [NotGate].
  Logic get out => output(_out);

  /// Constructs a [NotGate] with [a] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic a, {super.name = 'not'}) {
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
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }
    final a = inputs[_a]!;
    return '~$a';
  }
}

/// A generic unary gate [Module].
///
/// It always takes one input, and the output width is always 1.
class _OneInputUnaryGate extends Module with InlineSystemVerilog {
  /// Name for the input port of this module.
  late final String _a;

  /// Name for the output port of this module.
  late final String _y;

  /// The input to this gate.
  Logic get a => input(_a);

  /// The output of this gate (width is always 1).
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a) _op;
  final String _opStr;

  /// Constructs a unary gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as the
  /// prefix to the input signal name (e.g. if [_opStr] was "&", generated
  /// SystemVerilog may look like "&a").
  _OneInputUnaryGate(this._op, this._opStr, Logic a, {String name = 'ugate'})
      : super(name: name) {
    _a = Module.unpreferredName(a.name);
    _y = Module.unpreferredName('${name}_${a.name}');
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
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }
    final a = inputs[_a]!;
    return '$_opStr$a';
  }
}

/// A generic two-input bitwise gate [Module].
///
/// It always takes two inputs and has one output.  All ports have the
/// same width.
abstract class _TwoInputBitwiseGate extends Module with InlineSystemVerilog {
  /// Name for a first input port of this module.
  late final String _a;

  /// Name for a second input port of this module.
  late final String _b;

  /// Name for the output port of this module.
  late final String _y;

  /// An input to this gate.
  Logic get a => input(_a);

  /// An input to this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a, LogicValue b) _op;
  final String _opStr;

  /// Constructs a two-input bitwise gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was "&",
  /// generated SystemVerilog may look like "a & b").
  _TwoInputBitwiseGate(this._op, this._opStr, Logic a, dynamic b,
      {String name = 'gate2'})
      : super(name: name) {
    if (b is Logic && a.width != b.width) {
      throw Exception('Input widths must match,'
          ' but found $a and $b with different widths.');
    }

    final bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_${a.name}');
    _b = Module.unpreferredName('b_${bLogic.name}');
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
    } on Exception {
      // in case of things like divide by 0
      toPut = LogicValue.x;
    }
    y.put(toPut);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final a = inputs[_a]!;
    final b = inputs[_b]!;
    return '$a $_opStr $b';
  }
}

/// A generic two-input comparison gate [Module].
///
/// It always takes two inputs of the same width and has one 1-bit output.
abstract class _TwoInputComparisonGate extends Module with InlineSystemVerilog {
  /// Name for a first input port of this module.
  late final String _a;

  /// Name for a second input port of this module.
  late final String _b;

  /// Name for the output port of this module.
  late final String _y;

  /// An input to this gate.
  Logic get a => input(_a);

  /// An input to this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValue Function(LogicValue a, LogicValue b) _op;
  final String _opStr;

  /// Constructs a two-input comparison gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was ">",
  /// generated SystemVerilog may look like "a > b").
  _TwoInputComparisonGate(this._op, this._opStr, Logic a, dynamic b,
      {String name = 'cmp2'})
      : super(name: name) {
    if (b is Logic && a.width != b.width) {
      throw Exception('Input widths must match,'
          ' but found $a and $b with different widths.');
    }

    final bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_${a.name}');
    _b = Module.unpreferredName('b_${bLogic.name}');
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
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final a = inputs[_a]!;
    final b = inputs[_b]!;
    return '$a $_opStr $b';
  }
}

/// A generic two-input shift gate [Module].
///
/// It always takes two inputs and has one output of equal width to the primary
/// of the input.
class _ShiftGate extends Module with InlineSystemVerilog {
  /// Name for the main input port of this module.
  late final String _a;

  /// Name for the shift amount input port of this module.
  late final String _b;

  /// Name for the output port of this module.
  late final String _y;

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

  /// Constructs a two-input shift gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was ">>",
  /// generated SystemVerilog may look like "a >> b").
  _ShiftGate(this._op, this._opStr, Logic a, dynamic b,
      {String name = 'gate2', this.signed = false})
      : super(name: name) {
    final bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_${a.name}');
    _b = Module.unpreferredName('b_${bLogic.name}');
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
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final a = inputs[_a]!;
    final b = inputs[_b]!;
    final aStr = signed ? '\$signed($a)' : a;
    return '$aStr $_opStr $b';
  }
}

/// A two-input AND gate.
class And2Gate extends _TwoInputBitwiseGate {
  /// Calculates the AND of [a] and [b].
  And2Gate(Logic a, Logic b, {String name = 'and'})
      : super((a, b) => a & b, '&', a, b, name: name);
}

/// A two-input OR gate.
class Or2Gate extends _TwoInputBitwiseGate {
  /// Calculates the OR of [a] and [b].
  Or2Gate(Logic a, Logic b, {String name = 'or'})
      : super((a, b) => a | b, '|', a, b, name: name);
}

/// A two-input XOR gate.
class Xor2Gate extends _TwoInputBitwiseGate {
  /// Calculates the XOR of [a] and [b].
  Xor2Gate(Logic a, Logic b, {String name = 'xor'})
      : super((a, b) => a ^ b, '^', a, b, name: name);
}

/// A two-input addition module.
class Add extends _TwoInputBitwiseGate {
  /// Calculates the sum of [a] and [b].
  ///
  /// [b] can be either a [Logic] or [int].
  Add(Logic a, dynamic b, {String name = 'add'})
      : super((a, b) => a + b, '+', a, b, name: name);
}

/// A two-input subtraction module.
class Subtract extends _TwoInputBitwiseGate {
  /// Calculates the difference between [a] and [b].
  ///
  /// [b] can be either a [Logic] or [int].
  Subtract(Logic a, dynamic b, {String name = 'subtract'})
      : super((a, b) => a - b, '-', a, b, name: name);
}

/// A two-input multiplication module.
class Multiply extends _TwoInputBitwiseGate {
  /// Calculates the product of [a] and [b].
  ///
  /// [b] can be either a [Logic] or [int].
  Multiply(Logic a, dynamic b, {String name = 'multiply'})
      : super((a, b) => a * b, '*', a, b, name: name);
}

/// A two-input divison module.
class Divide extends _TwoInputBitwiseGate {
  /// Calculates [a] divided by [b].
  ///
  /// [b] can be either a [Logic] or [int].
  Divide(Logic a, dynamic b, {String name = 'divide'})
      : super((a, b) => a / b, '/', a, b, name: name);
}

/// A two-input modulo module.
class Modulo extends _TwoInputBitwiseGate {
  /// Calculates the module of [a] % [b].
  ///
  /// [b] can be either a [Logic] or [int].
  Modulo(Logic a, dynamic b, {String name = 'modulo'})
      : super((a, b) => a % b, '%', a, b, name: name);
}

/// A two-input equality comparison module.
class Equals extends _TwoInputComparisonGate {
  /// Calculates whether [a] and [b] are equal.
  ///
  /// [b] can be either a [Logic] or [int].
  Equals(Logic a, dynamic b, {String name = 'equals'})
      : super((a, b) => a.eq(b), '==', a, b, name: name);
}

/// A two-input comparison module for less-than.
class LessThan extends _TwoInputComparisonGate {
  /// Calculates whether [a] is less than [b].
  ///
  /// [b] can be either a [Logic] or [int].
  LessThan(Logic a, dynamic b, {String name = 'lessthan'})
      : super((a, b) => a < b, '<', a, b, name: name);
}

/// A two-input comparison module for greater-than.
class GreaterThan extends _TwoInputComparisonGate {
  /// Calculates whether [a] is greater than [b].
  ///
  /// [b] can be either a [Logic] or [int].
  GreaterThan(Logic a, dynamic b, {String name = 'greaterthan'})
      : super((a, b) => a > b, '>', a, b, name: name);
}

/// A two-input comparison module for less-than-or-equal-to.
class LessThanOrEqual extends _TwoInputComparisonGate {
  /// Calculates whether [a] is less than or equal to [b].
  ///
  /// [b] can be either a [Logic] or [int].
  LessThanOrEqual(Logic a, dynamic b, {String name = 'lessthanorequal'})
      : super((a, b) => a <= b, '<=', a, b, name: name);
}

/// A two-input comparison module for greater-than-or-equal-to.
class GreaterThanOrEqual extends _TwoInputComparisonGate {
  /// Calculates whether [a] is greater than or equal to [b].
  ///
  /// [b] can be either a [Logic] or [int].
  GreaterThanOrEqual(Logic a, dynamic b, {String name = 'greaterthanorequal'})
      : super((a, b) => a >= b, '>=', a, b, name: name);
}

/// A unary AND gate.
class AndUnary extends _OneInputUnaryGate {
  /// Calculates whether all bits of [a] are high.
  AndUnary(Logic a, {String name = 'uand'})
      : super((a) => a.and(), '&', a, name: name);
}

/// A unary OR gate.
class OrUnary extends _OneInputUnaryGate {
  /// Calculates whether any bits of [a] are high.
  OrUnary(Logic a, {String name = 'uor'})
      : super((a) => a.or(), '|', a, name: name);
}

/// A unary XOR gate.
class XorUnary extends _OneInputUnaryGate {
  /// Calculates the parity of the bits of [a].
  XorUnary(Logic a, {String name = 'uxor'})
      : super((a) => a.xor(), '^', a, name: name);
}

/// A logical right-shift module.
class RShift extends _ShiftGate {
  /// Calculates the value of [a] shifted right (logically) by [shamt].
  RShift(Logic a, Logic shamt, {String name = 'rshift'})
      :
        // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >>> shamt, '>>', a, shamt, name: name);
}

/// An arithmetic right-shift module.
class ARShift extends _ShiftGate {
  /// Calculates the value of [a] shifted right (arithmetically) by [shamt].
  ARShift(Logic a, Logic shamt, {String name = 'arshift'})
      :
        // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >> shamt, '>>>', a, shamt,
            name: name, signed: true);
}

/// A logical left-shift module.
class LShift extends _ShiftGate {
  /// Calculates the value of [a] shifted left by [shamt].
  LShift(Logic a, Logic shamt, {String name = 'lshift'})
      : super((a, shamt) => a << shamt, '<<', a, shamt, name: name);
}

/// A mux (multiplexer) module.
///
/// If [control] has value `1`, then [y] gets [d1].
/// If [control] has value `0`, then [y] gets [d0].
class Mux extends Module with InlineSystemVerilog {
  /// Name for the control signal of this mux.
  late final String _control;

  /// Name for the input selected when control is 0.
  late final String _d0;

  /// Name for the input selected when control is 1.
  late final String _d1;

  /// Name for the output port of this mux.
  late final String _y;

  /// The control signal for this [Mux].
  Logic get control => input(_control);

  /// [Mux] input propogated when [y] is `0`.
  Logic get d0 => input(_d0);

  /// [Mux] input propogated when [y] is `1`.
  Logic get d1 => input(_d1);

  /// Output port of the [Mux].
  Logic get y => output(_y);

  /// Constructs a multiplexer which passes [d0] or [d1] to [y] depending
  /// on if [control] is 0 or 1, respectively.
  Mux(Logic control, Logic d1, Logic d0, {super.name = 'mux'}) {
    if (control.width != 1) {
      throw Exception('Control must be single bit Logic, but found $control.');
    }
    if (d0.width != d1.width) {
      throw Exception('d0 ($d0) and d1 ($d1) must be same width');
    }

    _control = Module.unpreferredName('control_${control.name}');
    _d0 = Module.unpreferredName('d0_${d0.name}');
    _d1 = Module.unpreferredName('d1_${d1.name}');
    _y = Module.unpreferredName('y');

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
    if (inputs.length != 3) {
      throw Exception('Mux2 has exactly three inputs.');
    }
    final d0 = inputs[_d0]!;
    final d1 = inputs[_d1]!;
    final control = inputs[_control]!;
    return '$control ? $d1 : $d0';
  }
}

/// A two-input bit index gate [Module].
///
/// It always takes two inputs and has one output of width 1.
class IndexGate extends Module with InlineSystemVerilog {
  late final String _originalName, _indexName, _selectionName;

  /// The primary input to this gate.
  Logic get _original => input(_originalName);

  /// The bit index for this gate.
  Logic get _index => input(_indexName);

  /// The output of this gate.
  Logic get selection => output(_selectionName);

  /// Constructs a two-input bit index gate for an abitrary custom functional implementation.
  ///
  /// The bit [index] will be indexed as an output.
  /// [Module] is in-lined as SystemVerilog, it will use original[target], where target is [index.value.toInt()]
  IndexGate(Logic _original, Logic _index) : super() {
    _originalName = 'original_${_original.name}';
    _indexName = Module.unpreferredName('index_${_index.name}');
    _selectionName =
        Module.unpreferredName('${_original.name}_indexby_${_index.name}');

    addInput(_originalName, _original, width: _original.width);
    addInput(_indexName, _index, width: _index.width);
    addOutput(_selectionName, width: 1);

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
    if (_index.hasValidValue()) {
      final indexVal = _index.value.toInt();
      selection.put(_original.value.getRange(indexVal, indexVal + 1));
    } else {
      selection.put(LogicValue.x);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    final target = inputs[_originalName]!;
    final idx = inputs[_indexName]!;
    return '$target[$idx]';
  }
}

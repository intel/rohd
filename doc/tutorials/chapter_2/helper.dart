/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// helper.dart
/// A helper file that contains all the Helper module to print system verilog.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';

Future<void> displaySystemVerilog(Module mod) async {
  await mod.build();
  print('\nYour System Verilog Equivalent Code: \n ${mod.generateSynth()}');
}

class LogicInitialization extends Module {
  LogicInitialization(Logic a, Logic b) : super(name: 'logic_init') {
    a = addInput(a.name, a, width: a.width);
    b = addInput(b.name, b, width: b.width);
  }
}

class Part1LogicGate extends Module {
  Part1LogicGate(Logic a, Logic b, Logic c) : super(name: 'part_1_logic_gate') {
    a = addInput(a.name, a, width: a.width);
    b = addInput(b.name, b, width: b.width);
    c = addOutput(c.name, width: c.width);
  }
}

class AssignmentOperator extends Module {
  Logic get b => output('b');
  AssignmentOperator(
      Logic a, Logic b, void Function(Logic a, Logic b) assignment)
      : super(name: 'assignment_operator') {
    a = addInput(a.name, a, width: a.width);
    b = addOutput(b.name, width: b.width);

    assignment(a, b);
  }
}

class LogicGate extends Module {
  Logic get c => output('c');
  LogicGate(
      Logic a, Logic b, Logic c, void Function(Logic a, Logic b, Logic c) gate)
      : super(name: 'part_2_logic_gate') {
    a = addInput(a.name, a, width: a.width);
    b = addInput(b.name, b, width: b.width);
    c = addOutput(c.name, width: c.width);

    gate(a, b, c);
  }
}

class ConstantValue extends Module {
  Logic get a => input('a');
  ConstantValue(Logic a) : super(name: 'const_val') {
    a = addInput('a', a, width: a.width);
  }
}

class RangeSwizzling extends Module {
  Logic get d => output('d');
  Logic get e => output('e');
  Logic get f => output('f');
  RangeSwizzling(Logic a, Logic b, Logic c, Logic d, Logic e, Logic f,
      void Function(Logic a, Logic b, Logic c, Logic d, Logic e, Logic f) slice)
      : super(name: 'range_swizzling') {
    a = addInput(a.name, a, width: a.width);
    b = addInput(b.name, b, width: b.width);
    c = addInput(c.name, c, width: c.width);
    d = addOutput(d.name, width: d.width);
    e = addOutput(e.name, width: e.width);
    f = addOutput(f.name, width: f.width);

    slice(a, b, c, d, e, f);
  }
}

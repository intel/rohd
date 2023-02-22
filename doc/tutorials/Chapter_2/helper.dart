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

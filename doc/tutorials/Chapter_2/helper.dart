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
    c = addOutput('c', width: c.width);
  }
}

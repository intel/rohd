// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';

Future<void> displaySystemVerilog(Module mod) async {
  await mod.build();
  print('\nYour System Verilog Equivalent Code: \n ${mod.generateSynth()}');
}

class LogicInitialization extends Module {
  LogicInitialization(Logic a, Logic b) : super(name: 'logic_init') {
    final signal1 = addInput(a.name, a);
    final signal2 = addInput(b.name, b, width: b.width);
  }
}

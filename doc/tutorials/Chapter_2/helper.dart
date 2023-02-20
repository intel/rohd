// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

Future<void> displaySystemVerilog(Module mod) async {
  await mod.build();
  print('\nYour System Verilog Equivalent Code: \n ${mod.generateSynth()}');
}

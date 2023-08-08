// ignore_for_file: unused_local_variable, avoid_print

import 'package:rohd/rohd.dart';

enum PortDir { port }

class ModInterface extends Interface<PortDir> {
  final int width;
  Logic get port0 => port('port_0');
  Logic get port1 => port('port_1');
  Logic get port2 => port('port_2');
  Logic get port3 => port('port_3');
  Logic get port4 => port('port_4');
  Logic get port5 => port('port_5');
  Logic get port6 => port('port_6');
  Logic get port7 => port('port_7');
  Logic get port8 => port('port_8');
  Logic get port9 => port('port_9');

  ModInterface({this.width = 8}) {
    setPorts(
      List.generate(10, (index) => Port('port_$index')),
      [PortDir.port],
    );
  }
}

class ModuleA extends Module {
  Logic get out => output('out_res');
  ModuleA(ModInterface intf) : super(name: 'moduleA') {
    final modA = ModInterface()
      ..connectIO(
        this,
        intf,
        inputTags: {PortDir.port},
      );

    final out = addOutput('out_res');

    out <= modA.port0;
  }
}

class ModuleB extends Module {
  ModuleB(ModInterface intf, Logic clk) : super(name: 'moduleB') {
    final modB = ModInterface()
      ..connectIO(
        this,
        intf,
        outputTags: {PortDir.port},
      );

    Sequential(clk, [
      modB.port0 < Const(1),
      modB.port1 < Const(1),
      modB.port2 < Const(0),
      modB.port3 < Const(0),
      modB.port4 < Const(1),
      modB.port5 < Const(0),
      modB.port6 < Const(1),
      modB.port7 < Const(0),
      modB.port8 < Const(1),
      modB.port9 < Const(1),
    ]);
  }
}

class TestBench extends Module {
  Logic get out => output('data_out');
  final intf = ModInterface();

  TestBench(Logic clk) {
    final out = addOutput('data_out');

    // Output of module B connect to Module A
    final modA = ModuleA(intf);
    final modB = ModuleB(intf, clk);

    out <= modA.out;
  }
}

void main() async {
  final intf = ModInterface();
  final clk = SimpleClockGenerator(10).clk;
  final tb = TestBench(clk);
  await tb.build();

  print(tb.generateSynth());
}

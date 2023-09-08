// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

enum ToyCapsuleState { idle, coinInserted, dispensing }

class ToyCapsuleFSM extends Module {
  late StateMachine<ToyCapsuleState> _state;

  ToyCapsuleFSM(Logic clk, Logic reset, Logic btnDispense, Logic coin)
      : super(name: 'toy_capsule_fsm') {
    clk = addInput('clk', clk);
    reset = addInput(reset.name, reset);
    btnDispense = addInput(btnDispense.name, btnDispense);

    final toyCapsule = addOutput('toy_capsule');

    final states = [
      State(ToyCapsuleState.idle, events: {
        coin: ToyCapsuleState.coinInserted,
      }, actions: [
        toyCapsule < 0,
      ]),
      State(ToyCapsuleState.coinInserted, events: {
        btnDispense: ToyCapsuleState.dispensing
      }, actions: [
        toyCapsule < 0,
      ]),
      State(ToyCapsuleState.dispensing, events: {
        Const(1): ToyCapsuleState.idle
      }, actions: [
        toyCapsule < 1,
      ]),
    ];

    _state = StateMachine(clk, reset, ToyCapsuleState.idle, states);
  }

  StateMachine<ToyCapsuleState> get toyCapsuleStateMachine => _state;
  Logic get toyCapsule => output('toy_capsule');
}

Future<void> main(List<String> args) async {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final dispenseBtn = Logic(name: 'dispense_btn');
  final coin = Logic(name: 'coin_sensor');

  final toyCap = ToyCapsuleFSM(clk, reset, dispenseBtn, coin);
  await toyCap.build();

  print(toyCap.generateSynth());

  toyCap.toyCapsuleStateMachine.generateDiagram();

  reset.inject(1);

  WaveDumper(toyCap, outputPath: 'toyCapsuleFSM.vcd');

  Simulator.setMaxSimTime(100);
  Simulator.registerAction(25, () {
    reset.put(0);
  });

  Simulator.registerAction(30, () {
    coin.put(1);
  });

  Simulator.registerAction(35, () => dispenseBtn.put(1));

  Simulator.registerAction(50, () {
    dispenseBtn.put(0);
    coin.put(0);
  });

  await Simulator.run();
}

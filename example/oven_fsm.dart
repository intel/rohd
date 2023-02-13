import 'package:rohd/rohd.dart';

import './example.dart';

enum OvenStates { standby, cooking, paused, completed }

class Button extends Const {
  Button._(int super.value) : super(width: 2);
  Button.start() : this._(bin('00'));
  Button.pause() : this._(bin('01'));
  Button.resume() : this._(bin('10'));
}

class LEDLight extends Const {
  LEDLight._(int super.value) : super(width: 2);
  LEDLight.yellow() : this._(bin('00'));
  LEDLight.blue() : this._(bin('01'));
  LEDLight.red() : this._(bin('10'));
  LEDLight.green() : this._(bin('11'));
}

class OvenModule extends Module {
  OvenModule(Logic button, Logic reset) : super(name: 'OvenModule') {
    // input to FSM
    button = addInput('button', button, width: button.width);

    // output to FSM
    final led = addOutput('led', width: button.width);

    // add clock & reset
    final clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);

    // add time elapsed Counter
    final counterReset = Logic(name: 'counter_reset');
    final en = Logic(name: 'counter_en');
    final counter = Counter(en, counterReset, clk, name: 'counter_module');

    final states = [
      // Standby State
      State<OvenStates>(OvenStates.standby, events: {
        Logic(name: 'button_start')..gets(button.eq(Button.start())):
            OvenStates.cooking,
      }, actions: [
        led < LEDLight.blue().value,
        counterReset < 1,
        en < 0,
      ]),

      // Cooking State (Need to count here)
      State<OvenStates>(OvenStates.cooking, events: {
        Logic(name: 'button_pause')..gets(button.eq(Button.pause())):
            OvenStates.paused,
        Logic(name: 'counter_time_complete')..gets(counter.val.eq(4)):
            OvenStates.completed
      }, actions: [
        led < LEDLight.yellow().value,
        en < 1,
        counterReset < 0,
      ]),

      // Pause State
      State<OvenStates>(OvenStates.paused, events: {
        Logic(name: 'button_resume')..gets(button.eq(Button.resume())):
            OvenStates.cooking
      }, actions: [
        led < LEDLight.red().value,
        counterReset < 0,
        en < 0,
      ]),

      // Completed State
      State<OvenStates>(OvenStates.completed, events: {
        Logic(name: 'button_start')..gets(button.eq(Button.start())):
            OvenStates.cooking
      }, actions: [
        led < LEDLight.green().value,
        counterReset < 1,
        en < 0,
      ])
    ];

    StateMachine<OvenStates>(clk, reset, OvenStates.standby, states)
        .generateDiagram(outputPath: 'oven_fsm.md');
  }
}

void main() async {
  final button = Logic(name: 'button', width: 2);
  final reset = Logic(name: 'reset');

  // Create a counter Module
  final oven = OvenModule(button, reset);

  // build
  await oven.build();

  // print(oven.generateSynth());

  reset.inject(1);

  Simulator.registerAction(25, () => reset.put(0));
  Simulator.registerAction(25, () {
    button.put(bin('00'));
  });

  // Pause at 55 seconds of clock
  Simulator.registerAction(50, () {
    button.put(bin('01'));
  });

  // Resume at 60 seconds of clock
  Simulator.registerAction(70, () {
    button.put(bin('10'));
  });

  WaveDumper(oven, outputPath: 'example/oven.vcd');

  Simulator.registerAction(120, () {
    // ignore: avoid_print
    print('Simulation End');
  });

  Simulator.setMaxSimTime(120);

  await Simulator.run();
}

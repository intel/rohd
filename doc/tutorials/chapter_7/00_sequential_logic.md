# Content

- [What is Sequential Logic?](#what-is-sequential-logic)
- [Sequential Logic in ROHD](#sequential-logic-in-rohd)
- [Shift Register](#shift-register)
- [ROHD Simulator](#rohd-simulator)
- [Unit Test in Sequential Logic](#unit-test-in-sequential-logic)
- [Wave Dumper](#wave-dumper)
- [Exercise](#exercise)

## Learning Outcome

In this chapter:

- You will learn how to create a sequential logic that are equivalent to System Verilog `always_ff`. We will also review on what is `Simulator` and how to create unit test along with ROHD Simulator.

## What is Sequential Logic?

Sequential logic consists of elements that store state (such as flip-flops). In our previous chapter, we talked about combinational logic which input is only depend on the current state. But in sequential logic, past input will also be taken account before generate the current output.

## Sequential Logic in ROHD

In ROHD, a sequential module will consists of `Sequential()` class which map to system verilog `always_ff`. Just like `Combinationals()`, you can use `Conditionals()` inside `Sequential` block.

Dart doesn't have a notion of certain signals being "clocks" vs "not clocks". You can use any signal as a clock input to sequential logic, and have as many clocks of as many frequencies as you want.

## Shift Register

So, let us look into how to implement a shift register in ROHD.

A register is a digital circuit that use a group of flip-flops to store multiple bits of binary data (1 or 0). On the other hand, shift register is used to transfer the data in or out from register.

Positive or Negative Edge of the clock signal is used to initiate the bit from moving around the register which make this a sequential logic circuit. In our example, we will be using positive edge triggered of the clock.

Let start creating a shift register module and a main function to call on the shift register.

```dart
import 'package:rohd/rohd.dart';

class ShiftRegister extends Module {
  ShiftRegister();
}

void main() async {
  final shiftReg = ShiftRegister();
  await shiftReg.build();
  print(shiftReg.generateSynth());
}
```

Next, let define our inputs to the shift register. So, in our shift register we will need a reset pin `reset`, shift in pin `sin` and a clock `clk`. As for the output, there is one output pin shift out `sout`.

Let register or add the inputs and output to our ShiftRegister module.

```dart
class ShiftRegister extends Module {
  ShiftRegister(Logic clk, Logic reset, Logic sin,
      {super.name = 'shift_register'}) {
    clk = addInput('clk', clk);
    reset = addInput(reset.name, reset);
    sin = addInput(sin.name, sin, width: sin.width);

    // output width: Let say, we want 8 bit register
    const regWidth = 8;
    final sout = addOutput('sout', width: regWidth);
  }
}
```

Now, we declared our inputs and output pin. Next, we want to create a **local** signal name `data` that has same `width` with shift-out pin. This is the value that will get shift during the simulation.

Then, its time to declare the logic of the module. We want to start with creating a `Sequential()` block, that takes in a clock `clk`, a List of `Conditionals`, and a name for the Sequential (optional).

```dart
Sequential(clk, []);
```

For our conditionals, we want to wrap `If.block` that contains a List of `ElseIf` in the `Conditionals`. Note that the `ElseIf` here also mean `Iff` and `Else` that are implemented in ROHD framework. Don't confuse with dart `if` and `else`.

```dart
If.block();
```

To build our shift register, we want to say something like:

1. IF reset signal, then data will be set to 0
2. ELSE swizzle the sin with existing value
3. SET output port to the data

Our `ShiftRegister` module will be look like this instead.

```dart
class ShiftRegister extends Module {
  ShiftRegister(Logic clk, Logic reset, Logic sin,
      {super.name = 'shift_register'}) {
    clk = addInput('clk', clk);
    reset = addInput(reset.name, reset);
    sin = addInput(sin.name, sin, width: sin.width);

    // output width: Let say, we want 8 bit register
    const regWidth = 8;
    final sout = addOutput('sout', width: regWidth);

    // Local signal
    final data = Logic(name: 'data', width: regWidth); // 0000

    Sequential(clk, [
      If.block([
        Iff(reset, [data < 0]),
        Else([
          data < [data.slice(regWidth - 2, 0), sin].swizzle() 
        ])
      ]),
    ]);

    sout <= data;
  }
}
```

## ROHD Simulator

Now, it's time to dive in unit test and Simulation module in ROHD. ROHD simulator is a static class accessible as `Simulator` which implements a simple event-based simulator. All `Logic`s in Dart have `glitch` events which propagate values to connected `Logic`s downstream. In this way, ROHD propagates values across the entire graph representation of the hardware (without any `Simulator` involvement required).

The simulator has a concept of (unitless) time, and arbitrary Dart function can be registered to occur ar arbitrary times in the simulator. Asking the `Simulator` to run causes it to iterate through all deposit signals on `logic`s, it propagates values across the hardware.

- To register a function at an arbitrary timestamp, use `Simulator.registerAction`

```dart
final clk = SimpleClockGenerator(10).clk;
...
Simulator.registerAction(25, () => reset.put(0)); // put reset to 0 at time 25
```

- To set a maximum simulation time, use `Simulator.setMaxSimTime`

```dart
reset.inject
...
Simulator.setMaxSimTime(100); // set maximum time to 100
```

- To immediately end the simulation at the end of the current timestamp, use `Simulator.endSimulation`

```dart
Simulator.registerAction(75, Simulator.endSimulation); 
```

- To run just the next timestamp

```dart
await Simulator.tick();
print(flipFlop.q.value);

await Simulator.tick();
print(flipFlop.q.value);
```

- To run simulator ticks until completion, use `Simulator.run`

```dart
...
await Simulator.run();
```

- To reset the simulator, use `Simulator.reset`
  - Note that this only resets the `Simulator` and not any `Module`s or `Logic` values

```dart
// Normally you want to use this when doing unit test to make sure your simulator is in the clean state for every different test
await Simulator.reset();
```

- To add an action to the Simulator in the current timestep, use `Simulator.injectAction`

```dart
Simulator.registerAction(50, () async {
  Simulator.injectAction(() async {
    await Future<void>.delayed(const Duration(microseconds: 10));
    injectedActionExecuted = true;
  });
});
```

## Unit Test in Sequential Logic

Let see how we can actually build a unit test in `Sequential`. Before we start the simulation, let inject value of 1 to signals `reset` and `sin` to prevent our signal from being `z` value at the start.

We also can create a local function that print the flop of the clock. We can access the Simulator time using `.time` getter. Then, let us kick start the `Simulator` by setting its maximum simulation time and `.run()` the Simulator. Notice that we use `unawaited()` function instead of `await` because we want to do something with the positive edges. `unawaited()` here is basically telling Dart not to wait for `Simulator.run()` to complete before continuing.

```dart
void main() async {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final sin = Logic(name: 'sin', width: 4);

  final shiftReg = ShiftRegister(clk, reset, sin);
  await shiftReg.build();
  print(shiftReg.generateSynth());

  // Inject 1 to reset and 0 to shift in
  reset.inject(1);
  sin.inject(0);

  // Print the flop
  void printFlop([String message = '']) {
    print('@t=${Simulator.time}:\t'
        ' input=${sin.value}, output '
        '=${shiftReg.sout.value.toString(includeWidth: false)}\t$message');
  }

  // Set how long you want your simulator to run
  Simulator.setMaxSimTime(100);

  // Run the simulator but don't wait for it
  unawaited(Simulator.run());
}
```

## Wave Dumper

Let also add `WaveDumper` to view the waveform of the Simulation results.

```dart
void main() async {
  ...

  // Inject 1 to reset and 0 to shift in
  reset.inject(1);
  sin.inject(0);

  // Print the flop
  void printFlop([String message = '']) {
    print('@t=${Simulator.time}:\t'
        ' input=${sin.value}, output '
        '=${shiftReg.sout.value.toString(includeWidth: false)}\t$message');
  }

  // Set how long you want your simulator to run
  Simulator.setMaxSimTime(100);

  // Run the simulator but don't wait for it
  unawaited(Simulator.run());

  // Output the simulation waveform using WaveDumper
  WaveDumper(shiftReg,
        outputPath: 'doc/tutorials/chapter_7/shift_register.vcd');
}
```

Now, let print the flop before the first clock Positive edge. We can just call the `printFlop` function created previously.

```dart
...
WaveDumper(shiftReg,
        outputPath: 'doc/tutorials/chapter_7/shift_register.vcd');
printFlop('Before');
```

On next positive edge, we want to turn off the reset and shift in value of 1. To do that, we have to `await` for `nextPosedge` from clock, then put the value inside.

```dart
...
// wait for clock positive edge
await clk.nextPosedge;

// set the reset value to 0 and shift in 1
reset.put(0);
sin.put(1);
```

Then, we can use `expect()` function from the unit test in previous session to check for matcher on next posedge.

```dart
await clk.nextPosedge;
printFlop();
// Expect results flops by flops
expect(
    shiftReg.sout.value.toString(includeWidth: false), equals('00000001'));
```

Well, that its for unit test in Sequential Logic. After you finish the `Simulation`, you can use `Simulator.endSimulation()` to end the Simulator and await for `Simulator.simulationEnded`.

There is another method of writting unit test using which is using `Simulator.registerAction()`. But we will dive into that in the next chapter.

You can find the executable version of code at [shift_register.dart](shift_register.dart).

## Exercise

1. Can you try to build a D Flip-Flop using Sequential Logic?
    - Answer to this exercise can be found at [answers/exercise_1_d_flip_flop.dart](./answers/exercise_1_d_flip_flop.dart)

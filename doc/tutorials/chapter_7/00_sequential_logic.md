# Content

- [What is Sequential Logic?](#what-is-sequential-logic)
- Writting a unit test in Sequential Logic

## Learning Outcome

## What is Sequential Logic?

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

Next, let define our inputs to the shift register. So, in our shift register we will need a reset pin `reset`, shift in pin `sin` and a clock `clk`. As for the output, there are one output pin shift out `sout`.

Let register or add the inputs and output to our ShiftRegister module. Oh ya, we can add the name to our module as well. You can doing so this by adding `super.name='shift_register'` to the constructor.

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

void main() async {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final sin = Logic(name: 'sin', width: 4);

  final shiftReg = ShiftRegister(clk, reset, sin);
  await shiftReg.build();
  print(shiftReg.generateSynth());
}
```

Now, we declared our inputs and output pin. Next, we want to create a local signal name `data` that has same `width` with shift-out pin. This is the value that will get shift during the simulation.

Then, its time to declare the logic of the module. We want to start with creating a `Sequential()` block, that takes in a clock `clk`, a List of `Conditionals`, and a name for the Sequential (optional).

```dart
Sequential(clk, []);
```

For our conditionals, we want to wrap `IfBlock` that contains a List of `ElseIf` in the `Conditionals`. Note that the `ElseIf` here also mean `Iff` and `Else` that are implemented in ROHD framework. Don't confuse with dart `if` and `else`.

```dart
IfBlock();
```

To build our shift register, we want to say something like:

1. IF reset signal
    1.1 data will be set to 0
2. ELSE swizzle the 3 bits from LSB with the sin
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
      IfBlock([
        Iff(reset, [data < 0]),
        Else([
          data < [data.slice(2, 0), sin].swizzle() // left shift
        ])
      ]),
    ]);

    sout <= data;
  }
}
```

Now, its time for us to test for the simulation. Let see how we can actually build a unit test in `Sequential`. Before we start the simulation, let inject value of 1 to signals `reset` and `sin`.

```dart
void main() async {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final sin = Logic(name: 'sin', width: 4);

  final shiftReg = ShiftRegister(clk, reset, sin);
  await shiftReg.build();
  print(shiftReg.generateSynth());

  reset.inject(1);
  sin.inject(0);
}
```

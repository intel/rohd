# Content

- What is ROHD Module?
- First module (one input, one output, simple logic)
- Converting to SystemVerilog
- Exercise 1: Full Adder Module
- Composing modules within other modules

## Learning Outcome

In this chapter:

- You will learn what the ROHD module is and the criteria and rules for creating a module. We will then implement a Full-Adder and an N-Bit Full Adder, building upon the exercises completed previously, using the ROHD Module.

## What is ROHD Module?

If you have prior experience with System Verilog, you may already be familiar with the concept of a `Module`, as it is similar to what we are referring to in ROHD. You may wonder why we need a Module, as we have seen in previous tutorials that we can use ROHD without creating one. However, this is because we haven't delved into the details of simulation or System Verilog code generation.

In a typical ROHD framework, you will need a Module in order to unlock the capabilities of the `generateSynth()` and `Simulation()` functions. Therefore, it is important to learn about the ROHD module in order to increase the flexibility of hardware design. We will be using the `.build()` function extensively in later sequential circuits.

In ROHD, `Module` has inputs and outputs that connects them. However, there are severals rules that **MUST** be followed.

1. All logic within a `Module` must consume only inputs (from the `inputs` or `addInput` methods) to the Module directly or indirectly.

    ```dart
    class ExampleModule extends Module {
      ExampleModule(Logic a) {
        a = addInput('a', input);
        final b = addOutput('b');
        
        // Your Logic must use the Logic from addInput/inputs
        b <= a;
      }
    }
    ```

2. Any logic outside of a Module must consume the signals only via outputs (from the output or addOutput methods) of the Module.

    ```dart
    class ExampleModule extends Module {
      ExampleModule(Logic a) {
        a = addInput('a', input);
        final b = addOutput('b');
        
        // Your Logic must use the Logic from addInput/inputs
        b <= a;
      }
    }
    ```

3. Logic must be defined *before* the call to `super.build()`, which always must be called **at the end of the `build()` method** if it is overidden.

The `Module` base class has an optional String argument 'name' which is an instance name.

## First Module (One input, One output, Simple Logic)

Let's take an example of how to create a simple ROHD module. The example below shows a simple module created with one `input` and one `output`. Notice that `addInput()` and `addOutput()` are used, as mentioned previously, to register input and output ports. Another thing to note is that the logic of the module (i.e., output <= input) is included inside the constructor so that the `.build()` instruction will pick up the logic during the execution process.

```dart
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SimpleModule extends Module {
    // constructor
    SimpleModule(Logic input) {
        // register input port
        // add inputs in the constructor, passing in the Logic it is connected to
        // it's a good idea to re-set the input parameters so you don't accidentally use the wrong one
        input = addInput('input_1', input);

        // register output port
        // add outputs in the constructor as well
        // you can capture the output variable to a local variable for use
        var output = addOutput('out');

        // now you can define your logic
        // this example is just a passthrough from 'input' to 'output'
        output <= input;
  }
}

void main() async {
  final input = Const(1);
  final simModule = SimpleModule(input);
  await simModule.build();

  test('should return input value',
      () => expect(simModule.signals.first.value.toInt(), equals(1)));
}
```

Do note that the `build()` method returns a `Future<void>`, not just `void`. This is because the `build()` method is permitted to consume real wallclock time in some cases, for example for setting up cosimulation with another simulator. If you expect your build to consume wallclock time, make sure the Simulator is aware it needs to wait before proceeding.

That all about the basic of the module!

## Converting ROHD Module to System Verilog RTL

Next, we can see how extending your `Logic` to `Module` enables the generation of system Verilog code. Building on the previous example, we've made some slight modifications by adding `simModule.build()` and `simModule.generateSynth()`.

```dart
void main() async {
    final input = Const(1);
    final simModule = SimpleModule(input);
    
    // Add this code if haven't
    await simModule.build();

    // Print out system verilog code
    print(simModule.generateSynth());

    test('should return input value.',
          () => expect(simModule.signals.first.value.toInt(), equals(1)));

    // Add this to test on generate system verilog code
    test(
          'should generate system verilog code.',
        () => expect(simModule.generateSynth(), contains('module SimpleModule(')));
}
```

The output of the print above will show:

```dart
module SimpleModule(
input logic input_1,
output logic out
);
assign out = input_1;
endmodule : SimpleModule
```

## Exercise 1

1. Do you still remember how to create a full adder? Now, try to create ROHD Module full adder like above example. If you forgot how to create a full-adder, you can revise back at [chapter 3](../chapter_3/00_unit_test.md).

- Answer to this exercise can be found at [answers/full_adder.dart](./answers/full_adder.dart).

## Composing modules withon other modules

Now, your full-adder has been constructed as a module. Let's try to build an N-bit Adder module now. It's going to be similar to what we did in the basic generation. To recap, an N-bit Adder is composed of several Adders together. If you forget what is N-Bit adder, you can refer back to tutorial [chapter 4](../chapter_4/00_basic_generation.md).

As you can see in my `FullAdder` and `NBitAdder` classes, the `FullAdder` module class is composed within the `FullAdder` class, which allows the for loop in `NBitAdder` to generate `FullAdder` programmatically.

```dart
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class FullAdderResult {
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'c_out');
}

class FullAdder extends Module {
  final fullAdderresult = FullAdderResult();

  // Constructor
  FullAdder({
    required Logic a,
    required Logic b,
    required Logic carryIn,
    super.name = 'full_adder',
  }) {
    // Declare Input Node
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    carryIn = addInput('carry_in', carryIn, width: carryIn.width);

    // Declare Output Node
    final carryOut = addOutput('carry_out');
    final sum = addOutput('sum');

    final and1 = carryIn & (a ^ b);
    final and2 = b & a;

    // Use Combinational block
    Combinational([
      sum < (a ^ b) ^ carryIn,
      carryOut < and1 | and2,
    ]);

    fullAdderresult.sum <= output('sum');
    fullAdderresult.cOut <= output('carry_out');
  }

  FullAdderResult get fullAdderRes => fullAdderresult;
}

class NBitAdder extends Module {
  // Add Input and output port
  final sum = <Logic>[];
  Logic carry = Const(0);
  Logic a;
  Logic b;

  NBitAdder(this.a, this.b) {
    // Declare Input Node
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    carry = addInput('carry_in', carry, width: carry.width);

    final n = a.width;
    FullAdder? res;

    assert(a.width == b.width, 'a and b should have same width.');

    for (var i = 0; i < n; i++) {
      res = FullAdder(a: a[i], b: b[i], carryIn: carry);

      carry = res.fullAdderRes.cOut;
      sum.add(res.fullAdderRes.sum);
    }

    sum.add(carry);
  }

  LogicValue get sumRes => sum.rswizzle().value;
}

void main() async {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'b', width: 8);
  final nbitAdder = NBitAdder(a, b);

  await nbitAdder.build();

  // print(nbitAdder.generateSynth());

  test('should return 20 when A and B perform add.', () async {
    a.put(15);
    b.put(5);

    expect(nbitAdder.sumRes.toInt(), equals(20));
  });
}
```

Alright, that all for ROHD module. In next session we will be walk through Combinational Logic & Sequential Logic!

## Exercise 2

1. Build a N-bit Subtractor in ROHD Module.

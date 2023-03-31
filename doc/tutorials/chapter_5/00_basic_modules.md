# Content

- [What is ROHD Module?](#what-is-rohd-module)
- [First module (one input, one output, simple logic)](#first-module-one-input-one-output-simple-logic)
- [Converting ROHD Module to System Verilog RTL](#converting-rohd-module-to-system-verilog-rtl)
- [Exercise 1](#exercise-1)
- [Composing modules within other modules (N-Bit Adder)](#composing-modules-withon-other-modules-n-bit-adder)
- [Exercise 2](#exercise-2)

## Learning Outcome

In this chapter:

- You will learn what the ROHD module is and the criteria and rules for creating a module. We will then implement a Full-Adder and an N-Bit Adder, building upon the exercises completed previously, using the ROHD Module.

## What is ROHD Module?

If you have prior experience with System Verilog, you may already be familiar with the concept of a `Module`, as it is similar to what we are referring to in ROHD. You may wonder why we need a Module, as we have seen in previous tutorials that we can use ROHD without creating one. However, this is because we haven't delved into the details of simulation or System Verilog code generation.

In a typical ROHD framework, you will need a Module in order to unlock the capabilities of the `generateSynth()`, `Simulation()` functions and etc. Therefore, it is important to learn about the ROHD module in order to increase the flexibility of hardware design. We will be using the `.build()` function extensively in later sequential circuits.

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
      // getter (Create a getter function to expose your output)
      Logic get b => output('b');
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

1. Do you still remember how to create a full adder & full substractor? Now, try to create ROHD Module full adder and full subtractor like above example. You can revise back at [chapter 3](../chapter_3/00_unit_test.md).

- Answer to this exercise can be found at [answers/full_adder.dart](./answers/full_adder.dart) and [answers/full_subtractor.dart](./answers/full_subtractor.dart)

## Composing modules withon other modules (N-Bit Adder)

Now, your full-adder has been constructed as a module. Let's try to build an N-bit Adder module now. It's going to be similar to what we did in the basic generation. To recap, an N-bit Adder is composed of several Adders together. If you forget what is N-Bit adder, you can refer back to tutorial [chapter 4](../chapter_4/00_basic_generation.md).

As you can see in my `FullAdder` and `NBitAdder` classes, the `FullAdder` module class is composed within the `NBitAdder` class, which allows the for loop in `NBitAdder` to generate `FullAdder` programmatically. The difference here is instead of iterate the generation of the function, we iterate the generation of the ROHD module instead.

```dart
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
```

Alright, that all for the basic of the ROHD module. You can find the executable version of code at [n_bit_adder.dart](n_bit_adder.dart).

In the next session, we will be walk through the Combinational Logic & Sequential Logic!

## Exercise 2

1. Now, let try to build a N-bit Subtractor using ROHD Module.

- Answer to this exercise can be found at [answers/n_bit_subtractor.dart](./answers/n_bit_subtractor.dart).

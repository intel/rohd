## Content

- [Basic logic](./00-Basic_Logic.md#basic-logic)
  * [Logic](./00-Basic_Logic.md#logic)
    * [Exercise 1](./00-Basic_Logic.md#exercise-1)
  * [Logic Value & Width](./00-Basic_Logic.md#logic-value--width)
  * [Logic Gate: Part 1](./00-Basic_Logic.md#logic-gate-part-1)
    * [Assignment, Logical, Mathematical, Comparison Operations](./00-Basic_Logic.md#assignment-logical-mathematical-comparison-operations)
      * [Assignment](./00-Basic_Logic.md#assignment)
      * [Logical, Mathematical, Comparison Operations](./00-Basic_Logic.md#logical-mathematical-comparison-operations)
  * [Logic Gate: Part 2](./00-Basic_Logic.md#logic-gate-part-2)
    * [Non-synthesizable signal deposition (put)](./00-Basic_Logic.md#non-synthesizable-signal-deposition-put)
    * [Exercise 2](./00-Basic_Logic.md#exercise-2)
  * [Logic Gate: Part 3](./00-Basic_Logic.md#logic-gate-part-3)
    * [Exercise 3](./00-Basic_Logic.md#exercise-3)
- [Constants](./00-Basic_Logic.md#constants)
  * [Exercise 4](./00-Basic_Logic.md#exercise-4)
- [Bus Ranges and Swizzling](./00-Basic_Logic.md#bus-ranges-and-swizzling)

## Learning Outcome

Now that you have set up your development environment, let's get our hands dirty and start writing some ROHD code in this chapter.

In this chapter:

- You will learn about the fundamentals of ROHD variables, including how to define a logic, logic value, and initialize width for logic. You will learn by creating a simple 2-inputs and 1-output AND logic gate. In the process of creating the logic gate, you will understand how to use assignment, logical, mathematical, and comparison operations. You will also learn how to use non-synthesizable signal deposition (put) to send signals to the simulator to test your created logic gate.

- You will learn how to define constants, bus ranges, and swizzling to slice or access a range of bits from a bus.

# Basic Logic

## Logic

Like any programming language, ROHD has its own data types, which include `Logic` and `LogicValue`. `Logic` is fundamental to creating signals.

Note that in Dart, variable names are typically written in camelcase, such as `aSignal` and `thisIsVariable`. Visit this page to learn more [https://dart.dev/guides/language/effective-dart/style](https://dart.dev/guides/language/effective-dart/style). 

Below, let us look at how to create a `Logic` signal. In the example below, we can see that creation of `Logic` signals involved instantiate a `Logic` that can received `name` and `width` as an argument. 

```dart
// 1-bit unnamed signal. 
Logic unamedSignal = Logic();

// 8-bit bus named 'b'.
Logic bus = Logic(name: 'b', width: 8);

// You can use .toString() method to check for your signals details.
// Dart will assume you are using.toString() as default if not specify.
print(unamedSignal);
```

You can find the executable code at [a_logic.dart](./a_logic.dart).

### Exercise 1:

1. Create a 3-bit bus signal named `threeBitBus`.
2. Print the output of the signal. Explain what you see. Is there enough information in the output to verify that you have created the correct signal?

## Logic Value & Width
Now that we've learned how to create a Logic signal, let's explore how to access its value.

The value of a Logic signal is of type `LogicValue`, which has pre-defined constant bit values such as `x`, `z`, `one`, and `zero`.

To access the value of a Logic signal, you can simply call its `value` property. You can convert the value to an integer using the `toInt()` method, but note that this is only valid for signals that don't have any `x` or z bits. If the signal has more bits than can fit in a 64-bit integer, you'll need to use the `toBigInt()` method instead.

```dart
bus = Logic(name: 'threeBitBus', width: 3);
bigBus = Logic(name: 'bigBus', width: 65);
```

Let's take a look at an example of getting the value of the threeBitBus signal that we created earlier. 

```dart
// .put() is one way to simulate a signal on a Logic signal that has been
// created.
// We will come back to this in later section.
bus.put(1);

// Obtain the value of bus.
final busVal = bus.value;

print('\nNote:');

// output: 3'h1.
print('a) The hexadecimal string value of bus is $busVal.');

// Obtain the value of bus in Int
final busValInt = bus.value.toInt();

// output: 1.
print('b) The integer value of bus is $busValInt.');

// If you set your bus width larger than 64 bits.
// You have to use toBigInt().
bigBus.put(BigInt.parse('9223372036854775808'));
final bigBusValBigInt = bigBus.value.toBigInt();

// output: 9223372036854775808.
print('c) The big integer of bus is $bigBusValBigInt.');
```

You can find the executable code at [b_logic_width.dart](./b_logic_width.dart)

## Logic Gate: Part 1

By now, you have learned about `Logic` and `LogicValue`. Let's now dive into our first tutorial on Logic gate. Suppose we want to build a 2-input Logic `AND` gate.

![And Gate](./assets/And_gate.png)

To create our two-input Logic `AND` gate, we need to declare two input signals and one output signal, which means we will need to create a total of three Logic signals.

```dart
class LogicGate extends Module {
  // TODO(user): (Optional) Public attributes can register here.
  // -----------------------------------------------------------
  late final Logic a;
  late final Logic b;
  late final Logic c;

  LogicGate() : super(name: 'LogicGate') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // ----------------------------------------------------------
    a = Logic(name: 'input_a');
    b = Logic(name: 'input_b');
    c = Logic(name: 'output_c');

    // TODO(user): (Required) Declare your input and output port.
    // ----------------------------------------------------------
    // Add ports
    final signal1 = addInput('input_a', a, width: a.width);
    final signal2 = addInput('input_b', b, width: b.width);
    final signal3 = addOutput('output_c', width: c.width);
  }
}
```

That's all! We have created all the ports required. You can find the executable code at [c_logic_gate_part_1.dart](./c_logic_gate_part_1.dart). Next, let's take a look at the operators in ROHD.

## Assignment, Logical, Mathematical, Comparison Operations

### Assignment

To assign the value of one signal to another signal, use the `<=` operator. This is a hardware synthesizable assignment that connects two wires together. 

Let's take a look at an example of how to assign a Logic signal `a` to signal `b`.

```dart
class AssignmentOperator extends Module {
  // TODO(user): (Optional) Public attributes can register here.
  // -----------------------------------------------------------
  late final Logic a;
  late final Logic b;

  AssignmentOperator() : super(name: 'Assignment') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // ----------------------------------------------------------
    a = Logic(name: 'signal_a');
    b = Logic(name: 'signal_b');

    // TODO(user): (Required) Declare your input and output port.
    // ----------------------------------------------------------
    // In this case, b is connected to a which means they will have the same value.
    final signal1 = addInput('a', a, width: a.width);
    final signal2 = addOutput('b', width: b.width);

    // TODO(user): (Optional) Logic Operations.
    // ----------------------------------------
    signal2 <= signal1;
  }
}

void main() async {
  // ...

  // TODO(user): (Optional) Simulate your Module.
  // --------------------------------------------
  assignOperator.a.put(1);

  // we can access the signal by naviagate through the iterable.
  final portB =
      assignOperator.signals.firstWhere((element) => element.name == 'b');
  print('The value of b is ${portB.value}.');
}
```

You can find the executable code at [d_assignment_operator.dart](./d_assignment_operator.dart). 

### Logical, Mathematical, Comparison Operations

In ROHD, we have operators that are similar to those in SystemVerilog. This makes it easier for users to learn and pick up the language.

Below are the operations provided in ROHD. 

You **do not need to copy and paste for this section**. Just look and remember few of the important operators.

```dart
a_bar     <=  ~a;      // not
a_and_b   <=  a & b;   // and
a_or_b    <=  a | b;   // or
a_xor_b   <=  a ^ b;   // xor
and_a     <=  a.and(); // unary and
or_a      <=  a.or();  // unary or
xor_a     <=  a.xor(); // unary xor
a_plus_b  <=  a + b;   // addition
a_sub_b   <=  a - b;   // subtraction
a_times_b <=  a * b;   // multiplication
a_div_b   <=  a / b;   // division
a_mod_b   <=  a % b;   // modulo
a_eq_b    <=  a.eq(b)  // equality              NOTE: == is for Object equality of Logic's
a_lt_b    <=  a.lt(b)  // less than             NOTE: <  is for conditional assignment
a_lte_b   <=  a.lte(b) // less than or equal    NOTE: <= is for assignment
a_gt_b    <=  (a > b)  // greater than          NOTE: careful with order of operations, > needs parentheses in this case
a_gte_b   <=  (a >= b) // greater than or equal NOTE: careful with order of operations, >= needs parentheses in this case
answer    <=  mux(selectA, a, b) // answer = selectA ? a : b
```

Great, now that you've learned all about our operators, let's continue our journey and create an `AND` gate. 

## Logic Gate: Part 2

We can use the `&` operator that we learned earlier to create an `AND` logic gate.

```dart
class LogicGate extends Module {
  
  // TODO(user): (Optional) Public attributes can register here.
  // -----------------------------------------------------------
  late final Logic a;
  late final Logic b;
  late final Logic c;

  LogicGate() : super(name: 'LogicGate') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // ------------------------------------------------------------
    // Create input and output signals
    a = Logic(name: 'input_a');
    b = Logic(name: 'input_b');
    c = Logic(name: 'output_c');

    // TODO(user): (Required) Declare your input and output port.
    // ----------------------------------------------------------
    // Add ports
    final signal1 = addInput('input_a', a, width: a.width);
    final signal2 = addInput('input_b', b, width: b.width);
    final signal3 = addOutput('output_c', width: c.width);

    // TODO(user): (Optional) Logic Operations.
    // ----------------------------------------

    // Note that the & symbols is the AND operator
    c <= signal1 & signal2;
    signal3 <= c;
  }
}
```

### Exercise 2:

1. Can you optimize the code? Can you remove the redundance from the code? 

You can find the executable code at [e_logic_gate_part_2.dart](./e_logic_gate_part_2.dart). Congratulations! You have created your logic gate. Let's move on to the next section to test our gate.

### Non-synthesizable signal deposition (put)

Do you still remember the `put()` function that was used in the previous section? It is used to send a simulated signal to the input `Logic`.

For testbench code or other non-synthesizable code, you can use `put` on any `Logic` to deposit a value on the signal.

Now let's see an example of how to deposit signals for testing using `put`. At this point, you should be familiar with how you can deposit signals.

Note: This section of code **does not need to run**. 

```dart
b = Logic(width:4);

// you can put an integer directly into a signal.
a.put(4);
```

## Logic Gate: Part 3

Now, we can test our logic gate with the simulator.

```dart
// ...

void main() async {
  // ...

  // TODO(user): (Optional) Simulate your Module.
  // --------------------------------------------

  // Let build a truth table
  int portC;
  print('\nBuild Truth Table: ');
  for (var i = 0; i <= 1; i++) {
    for (var j = 0; j <= 1; j++) {
      basicLogic.a.put(i);
      basicLogic.b.put(j);
      // print('a: $i, b: $j c: ${basicLogic.c.value.toInt()}');
      portC = basicLogic.signals
          .firstWhere((element) => element.name == 'output_c')
          .value
          .toInt();
      print('a: $i, b: $j c: $portC');
    }
  }
}
```

You can find the executable code at [Basic Logic](./f_logic_gate_part_3.dart).

Congratulations!!! You have successfully build your first gate! 

### Exercise 3:

1. Build OR or NOR or XOR gate using ROHD.

# Constants

In ROHD, constants can often be inferred by ROHD automatically, but can also be explicitly defined using `Const`, which extends `Logic`.

```dart
class ConstantLogic extends Module {
  ConstantLogic() : super(name: 'ConstantLogic') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // ------------------------------------------------------------
    // Declare Constant
    final x = Const(5, width: 16);
    print('The value of constant x is: ${x.value.toInt()}');

    // TODO(user): (Required) Declare your input and output port.
    // ----------------------------------------------------------
    // Add ports
    final signal1 = addInput('const_x', x, width: x.width);
  }
}
```

### Exercise 4:

1. Create a constant of value 10 and assign to a Logic input.

# Bus Ranges and Swizzling

In the previous module, we learned about the `width` property of `Logic`. Now, we can perform operations like slicing and swizzling on `Logic` values.

We can access multi-bit buses using single bits, ranges, or by combining multiple signals. Additionally, we can use operations like slicing and swizzling on `Logic` values.

```dart
// TODO(user): (Optional) Change [YourModuleName] to your own module name.
// -----------------------------------------------------------------------
class RangeSwizzling extends Module {
  // TODO(user): (Optional) Public attributes can register here.
  // ------------------------------------------------------------
  late final Logic a;
  late final Logic b;
  late final Logic c;
  late final Logic d;
  late final Logic e;
  late final Logic f;

  // TODO(user): (Optional) 'ModuleName' can change to your own module name.
  // -----------------------------------------------------------------------
  RangeSwizzling() : super(name: 'RangeSwizzling') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // ------------------------------------------------------------
    // Declare Constant
    a = Logic(name: 'signal_a', width: 4);
    b = Logic(name: 'signal_b', width: 8);
    c = Const(7, width: 5);
    d = Logic(name: 'signal_d');
    e = Logic(name: 'signal_e', width: d.width + c.width + a.width);
    f = Logic(name: 'signal_f', width: d.width + c.width + a.width);

    // TODO(user): (Required) Declare your input and output port.
    // ----------------------------------------------------------
    // Add ports
    final signal1 = addInput('a', a, width: a.width);
    final signal2 = addInput('b', b, width: b.width);
    final signal3 = addInput('c', c, width: c.width);
    final signal4 = addInput('d', d, width: d.width);
    final signal5 = addInput('e', e, width: e.width);
    final signal6 = addInput('f', f, width: f.width);

    // TODO(user): (Optional) Logic Operations.
    // ----------------------------------------
    // Add ports
    final signal1 = addOutput('output_d', width: d.width);
    final signal2 = addOutput('output_e', width: e.width);
    final signal3 = addOutput('output_f', width: f.width);

    // assign d to the top bit of a
    // construct e by swizzling bits from b, c, and d
    // here, the MSB is on the left, LSB is on the right
    d <= b[7];
    signal1 <= d;

    // value:
    // swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB) ,
    // e = [1 00111 1110] = [d, c, a]
    e <= [d, c, a].swizzle();
    signal2 <= e;

    // alternatively, do a reverse swizzle
    // (useful for lists where 0-index is actually the 0th element)
    //
    // Here, the LSB is on the left, the MSB is on the right
    // right swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB),
    // e = [1110 00111 1] - [a, c, d]
    f <= [d, c, a].rswizzle();
    signal3 <= f;
  }
}

void main() async {
  // Instantiate Module and display system verilog

  // TODO(user): (Optional) Update [YourModuleName].
  // ----------------------------------------------
  final rangeSwizzling = RangeSwizzling();
  await displaySystemVerilog(rangeSwizzling);

  // TODO(user): (Optional) Simulate your Module.
  // --------------------------------------------
  print('\n');

  // assign b to the bottom 3 bits of a
  // input = [1, 1, 1, 0], output = 110
  rangeSwizzling.a.put(bin('1110'));
  print('a.slice(2, 0):'
      ' ${rangeSwizzling.a.slice(2, 0).value.toString(includeWidth: false)}');

  rangeSwizzling.b.put(bin('11000100'));
  print('a[7]: ${rangeSwizzling.b[7].value.toString(includeWidth: false)}');
  print('a[0]: ${rangeSwizzling.b[0].value.toString(includeWidth: false)}');
  print('e: ${rangeSwizzling.e.value.toString(includeWidth: false)}');
  print('f: ${rangeSwizzling.f.value.toString(includeWidth: false)}');
}
```

ROHD does not support assignment to a subset of a bus. That is, you cannot do something like `e[3] <= d`. Instead, you can use the withSet function to get a copy with that subset of the bus assigned to something else. This applies for both Logic and LogicValue. For example:

**You do not need to run this code.**
```dart
// reassign the variable `e` to a new `Logic` where bit 3 is set to `d`
e = e.withSet(3, d);
```

----------------
2023 February 14
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

 
Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause

# Basic Logic

## Introduction

Now that you have set up your development environment, let's get our hands dirty and start writing some Dart code with ROHD in this chapter. 

In this section, you will learn how to construct your first basic logic gate.

### Learning Outcome

After completing this section, you should be familiar with the basic concepts of gate creation and common ROHD operators, including:

* Logic
* Logic Value
* Logic Width
* Operators
* Constants
* Ranges
* Swizzling

## Logic, Logic Value, Width

Like any programming language, ROHD has its own data types, which include `Logic` and `LogicValue`. `Logic` is fundamental to creating signals.

Note that in Dart, variable names are typically written in camelcase, such as aSignal and thisIsVariable.

```dart
// 1-bit unnamed signal
Logic unamedSignal = Logic();

// 8-bit bus named 'b'
Logic bus = Logic(name: 'b', width: 8);

// You can use toString() method to check for your signals details
print(unamedSignal.toString());
```

In the example above, we can see that creation of `Logic` signals involved instantiate the `Logic` object that can received name and width.

### Exercise

1. Create a 3 bit bus signals with name `threeBitBus`.
2. Print the output and explain what do you see. Does it have enough information to proof that you are creating the right signal?

Now, we learnt how to create a `Logic` signal. Next, we are going to see how to access the value of the signal created.

Well, the approaches is pretty direct which is just through calling `value` property of the `Logic`. You can convert the value to `int` through `toInt()` function provide but note that its only applicable for valid signals (no X and Z). Another things to note here, If the signals has **more bits than dart `int` bits(64 bits, usually)**, you have to use `toBigInt()` instead.

The value of `Logic` is of type `LogicValue`, with pre-defined constant bit values `x`, `z`, `one`, and `zero`.

Let see an example of getting the bus value from previous bus created.

```dart
// put is one of the ways to send simulate signal to the Logic created.
// We will come back to this in later section.
bus.put(1);

// Obtain the value of bus
LogicValue busVal = bus.value; 

// Obtain the value of bus in Int
int busValInt = bus.value.toInt(); 

// If you set your bus width larger than 64 bits. 
// You have to use toBigInt()
Logic bigBus = Logic(name: 'b', width: 65);

bigBus.put(BigInt.parse("9223372036854775808"));
LogicValue bigBusValBigInt = bigBus.value.toBigInt();

// output: 8'h1
print(busVal);

// output: 1
print(busValInt);

// output: 9223372036854775808
print(bigBusValBigInt);
```

## Logic Gate Part 1

As of now, you already learn what is `Logic` and `LogicValue` all about. Let now start to dive in our Logic gate first tutorials. Say, we want to build a
2-input Logic **AND gate**.

In our two-input logic AND gate, we will need to first declare 2-input signals and 1 output signal which we will need to create a `total of 3 Logic signals`.

```dart
import 'package:rohd/rohd.dart';

void main() {
  // Create input and output signals
  final a = Logic(name: 'input_a');
  final b = Logic(name: 'input_b');
  final c = Logic(name: 'output_c');
}
```

Yup, that all! We created all the port required. Next, Let us check on the operators in ROHD.

## Assignment, Logical, Mathematical, Comparison Operations

### Assignments

To assign one signal to the value of another signal, use the `<=` operator. This is a hardware synthesizable assignment connecting two wires together.

Let us see an example of how to assign a Logic signal `a` to signal `b`.

```dart
Logic a = Logic(name: 'signal_a');
Logic b = Logic(name: 'signal_b');

// In this case, b is connected to a which make them yields the same value.
a <= b;
```

### Logical, Mathematical, Comparison Operations

In ROHD, we have our operators similar to those in SystemVerilog which aims to make user easier to learn and pick up.

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

Well, so you learnt all about our operators! Let continue our journey on `AND gate` creation. To create `AND` logic gate, we can use the `&` operator from above!

### Logic Gate: Part 2

```dart
import 'package:rohd/rohd.dart';

void main() {
  // Create input and output signals
  final a = Logic(name: 'input_a');
  final b = Logic(name: 'input_b');
  final c = Logic(name: 'output_c');

  // Create an AND logic gate
  // This assign c to the result of a AND b
  c <= a & b;
}
```

Congratulation! You created your logic gate! Let head to the next section to test our gate.

## Non-synthesizable signal deposition (put)

Still remember the `put()` function used on the previous section? This is used to send simulated signal to the input `Logic`.

For testbench code or other non-synthesizable code, you can use `put` or `inject` on any Logic to **deposit a value** on the signal. The two functions have similar behavior, but inject is shorthand for calling `put` inside of `Simulator.injectAction`, which allows the deposited change to propogate within the same Simulator tick. Generally, you will want to use `inject` for **testbench interaction with a design**.

Well, let see an example of how we deposit a signals for testing. Both `put` and `inject` is used.

```dart
b = Logic(width:4);

// you can put an int directly on a signal
a.put(4);

// Use only with Simulator tick
a.inject(4);
```

### Logic Gate: Part 3

Now, we can test our logic gate with the simulator.

```dart
import 'package:rohd/rohd.dart';

void main() {
  // Create input and output signals
  final a = Logic(name: 'input_a');
  final b = Logic(name: 'input_b');
  final c = Logic(name: 'output_c');

  // Create an AND logic gate
  // This assign c to the result of a AND b
  c <= a & b;

  // let try with simple a = 1, b = 1
  // a.put(1);
  // b.put(1);
  // print(c.value.toInt());

  // Let build a truth table
  for (int i = 0; i <= 1; i++) {
    for (int j = 0; j <= 1; j++) {
      a.put(i);
      b.put(j);
      print("a: $i, b: $j c: ${c.value.toInt()}");
    }
  }
}
```

Congratulations!!! You have successfully build your first gate! 

Exercise:

1. Build OR, NOR, XOR gate using ROHD.

## Constants

In ROHD, constants can often be inferred by ROHD automatically, but can also be explicitly defined using Const, which extends Logic.

```dart
// a 16 bit constant with value 5
var x = Const(5, width:16);
```

### Exercise

1. Create a constant of value 10 and assign to a Logic input.

Answer:

```dart
Logic a = Logic(width: 5);
a <= Const(10, width: 5);
print(a.value.toInt());
```

## Bus Ranges and Swizzling

In the previous module, we learn about `width` in the `Logic`. Now, we are going to see some operations like slicing and swzzling can be done.

Multi-bit busses can be accessed by single bits and ranges or composed from multiple other signals. Slicing, swizzling, etc. are also accessible on LogicValues.

```dart
var a = Logic(width:8),
    b = Logic(width:3),
    c = Const(7, width:5),
    d = Logic(),
    e = Logic(width: 9);


// assign b to the bottom 3 bits of a
b <= a.slice(2,0);

// assign d to the top bit of a
d <= a[7];

// construct e by swizzling bits from b, c, and d
// here, the MSB is on the left, LSB is on the right
e <= [d, c, b].swizzle();

// alternatively, do a reverse swizzle (useful for lists where 0-index is actually the 0th element)
// here, the LSB is on the left, the MSB is on the right
e <= [b, c, d].rswizzle();
```

ROHD does not support assignment to a subset of a bus. That is, you cannot do something like e[3] <= d. Instead, you can use the withSet function to get a copy with that subset of the bus assigned to something else. This applies for both Logic and LogicValue. For example:

```dart
// reassign the variable `e` to a new `Logic` where bit 3 is set to `d`
e = e.withSet(3, d);
```

## End of Section Code

```dart
import 'package:rohd/rohd.dart';

void main() {
  // Create input and output signals
  final a = Logic(name: 'input_a');
  final b = Logic(name: 'input_b');
  final c = Logic(name: 'output_c');

  // Create an AND logic gate
  // This assign c to the result of a AND b
  c <= a & b;

  // let try with simple a = 1, b = 1
  // a.put(1);
  // b.put(1);
  // print(c.value.toInt());

  // Let build a truth table
  for (int i = 0; i <= 1; i++) {
    for (int j = 0; j <= 1; j++) {
      a.put(i);
      b.put(j);
      print("a: $i, b: $j c: ${c.value.toInt()}");
    }
  }
}
```
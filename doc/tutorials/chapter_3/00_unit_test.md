## Content

- [Introduction to Test Driven Development](./00_unit_test.md#introduction-to-test-driven-development)
- [What is a Full-Adder?](./00_unit_test.md#what-is-a-full-adder)
- [Create a Full-Adder with TDD](./00_unit_test.md#create-full-adder-with-tdd)

## Learning Outcome

In this chapter:

- You will learn how to create a full-adder with Test Driven Development (TDD).

## Introduction to Test Driven Development

ROHD encourages the use of test-driven development (TDD) when designing or developing programs. In this module, we will explore how to implement TDD using the Dart programming language.

TDD is a software development approach in which test cases are created to specify and validate the expected behavior of the code. Essentially, test cases for each piece of functionality are written and executed before writing any code. If the test fails, new code is written until it passes the test, resulting in simpler and bug-free code.

## What is a Full-Adder?

A Full Adder is an adder that takes three inputs and produces two outputs: the first two inputs are A and B, while the third input is a carry-in (C-IN). The output carry is designated as C-OUT, while the normal output is designated as S (SUM). A Full Adder logic is designed to handle up to eight inputs to create a byte-wide adder and can cascade the carry bit from one adder to another. We use a Full Adder when a carry-in bit is available because a 1-bit half-adder cannot take a carry-in bit, and another 1-bit adder must be used instead. A 1-bit Full Adder adds three operands and generates a 2-bit result.

Below is the circuit diagram of full-adder. From the diagram, we can see that the output `SUM` is the result of `XOR(XOR(A, B), C-IN)`, while `C-Out` is the result of `OR(AND(C-IN, XOR(A, B)), AND(B, A))`.

![Full Adder](./assets/full_adder_circuit.png)

The truth table of full-adder are shown below:

| A | B | C-IN | SUM | C-Out |
| -- | -- | -- | -- | -- |
| 0 | 0 | 0 | 0 | 0 |
| 0 | 0 | 1 | 1 | 0 |
| 0 | 1 | 0 | 1 | 0 |
| 0 | 1 | 1 | 0 | 1 |
| 1 | 0 | 0 | 1 | 0 |
| 1 | 0 | 1 | 0 | 1 |
| 1 | 1 | 0 | 0 | 1 |
| 1 | 1 | 1 | 1 | 1 |

## Create Full-Adder with TDD

Before we start our development, we need to import dart and rohd packages. Then, we want to create a main function.

```dart
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
    // your rohd implmentation here!
}
```

### Step 1: Create a failing test (Red Hat)

In TDD, we start by creating a failing test known as red hat. Let create a test case that test for SUM.


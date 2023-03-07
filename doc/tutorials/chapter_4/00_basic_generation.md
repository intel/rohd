# Content

- [What is n-bit adder?](./00_basic_generation.md#what-is-n-bit-adder)
- [Create a unit-test](./00_basic_generation.md#create-a-unit-test)
- [Create Dart function and class](./00_basic_generation.md#create-dart-function-and-class)

## Learning Outcome

In this chapter:

- You learn how to create an n-bit adder by utilizing dart function and class. You will start by writting unit test and slowly implement the function of the n-bit adder.

## What is n-bit adder?

N-bit adder is also known as ripple carry carry adder. It is a digital circuit that generate the sum of two binary numbers.

N-Bit adder is designed by connecting full adders in series. The figure below shows 4-bit adder. The `a` and `b` is the input binary, `c` is the carry, and `s` is the sum.

![ripple carry adder](./assets/ripple_carry_adder.png)

So, let say we have:

a = 0100
b = 0111

The result will be:

s = 1011

## Create a unit test

Let start by creating a `main()` function that received two-inputs `Logic a` and `Logic b`.

We also want to create a function that contains the logic of the nBitAdder.

An output name `sum` can be also created. Remember that `sum` is the final value that are generated from our `nBitAdder` function. Therefore, its can be expressed with `final sum = nBitAdder(a, b)`. This would mean the variable `sum` is the return output from nBitAdder function.

Next, let create our test that expect to see 10 when both input is 5. The code snippet below shows the implementation.

```dart
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'a', width: 8);

  final sum = nBitAdder(a, b);

  test('should return 10 when both input is 5', () {
    a.put(5);
    b.put(5);

    expect(sum.value.toInt(), equals(10));
  });
}

Logic nBitAdder(Logic a, Logic b) {
  return Const(0);
}
```

Well, if you run the code. You will see your test fail as its expect to see the value of 10 instead of our hardcoded 0. That okay, we will make it work in the next step.

## Create Dart function and class

If we look back to the n-bit adder diagram previosuly, you will notice that n-bit adder is just a repetition of the single full-adder from our previous tutorial.

So, let start by creating a full adder function `fullAdder` that take in `Logic a`, `Logic b`, and `carryIn`. Notice that in full adder, we have `sum` and `cOut` as the output where we can create a custom class named `FullAdderResult` which hold `sum` and `cOut`.

```dart
// Result class of full adder
class FullAdderResult {
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'c_out');
}

// fullAdder function that has a return type of FullAdderResult
FullAdderResult fullAdder(Logic a, Logic b, Logic carryIn) {
  final and1 = carryIn & (a ^ b);
  final and2 = b & a;

  final res = FullAdderResult();
  res.sum <= (a ^ b) ^ carryIn;
  res.cOut <= and1 | and2;

  return res;
}
```

Next, we want to remove the `Const(0)` in `nBitAdder()`, we don't need this anymore as we will be filling up the function with concreate implementation.

Let start by making sure the width in `a` and `b` is the same by using `assert`. Next, we can create a `carry` variable that contains `Const(0)` and also create a List that hold Logic signals `sum` and final output of `carry`.

We can create for loop to iterate over all the bits in the widths by instatiating the FullAdder object and passed in value of a`[i]`, `b[i]` and `carry` to the constructor.

Since `FullAdder` will return `FullAdderResult`, we can access the properties of carry by `res.cOut` and replace the value of previous carry. The result of the `res.sum` will be append to the list `sum`. The iteration will loop through all the bits and add the final `carry` value to the `sum` list.

The we will use `rswizzle()` on `sum` to perform a concatenation operation on the list of signals, where index 0 of this list is the least significant bit(s).

You will see your `nBitAdder` function as below.

```dart
Logic nBitAdder(Logic a, Logic b) {
  assert(a.width == b.width, 'a and b should have same width.');

  final n = a.width;
  Logic carry = Const(0);
  final sum = <Logic>[];

  for (var i = 0; i < n; i++) {
    final res = fullAdder(a[i], b[i], carry);
    carry = res.cOut;
    sum.add(res.sum);
  }

  sum.add(carry);

  return sum.rswizzle();
}
```

Now, run your test again and you will see All tests passed! You can find the executable code at [basic_generation.dart](./basic_generation.dart) while the system verilog equivalent executable code can be found at [basic_generation_sv.dart](./basic_generation_sv.dart)

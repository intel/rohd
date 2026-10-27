---
title: "Sequentials"
permalink: /docs/sequentials/
excerpt: "Sequentials"
last_modified_at: 2022-12-06
toc: true
---

ROHD has a basic [`FlipFlop`](https://intel.github.io/rohd/rohd/FlipFlop-class.html) module that can be used as a flip flop.  You can use the shorthand [`flop`](https://intel.github.io/rohd/rohd/flop.html) to construct a `FlipFlop`.  For more complex sequential logic, use the `Sequential` block described in the Conditionals section.

Dart doesn't have a notion of certain signals being "clocks" vs. "not clocks".  You can use any signal as a clock input to sequential logic, and have as many clocks of as many frequencies as you want.

## Flops with Enum Values

A `flop` whose data input is a [`LogicEnum`](./A23-logic-enums.md) can use an enum member as its `resetValue`. The register resets to that member's encoding, and the output keeps the enum type when you use the explicit form:

```dart
enum MyState { idle, run, done }

final stateD = LogicEnum<MyState>(MyState.values, name: 'stateD');
final stateQ = flop<LogicEnum<MyState>>(clk, stateD,
    reset: reset, resetValue: MyState.idle);
```

If you write `q <= flop(clk, stateD, reset: reset, resetValue: MyState.idle)` without the type argument, Dart infers a plain `Logic` output. The reset still uses the enum's encoding, so the result is the same in simulation and SystemVerilog, but the output is not typed as the enum.

Use `Logic.from(...)` when you want a plain packed register, for example when
the data input is a `Const`:

```dart
final registered = flop(clk, Logic.from(Const(1)));
```

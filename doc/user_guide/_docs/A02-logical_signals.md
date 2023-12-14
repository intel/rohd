---
title: "Logical Signals"
permalink: /docs/logical-signals/
excerpt: "Logic signals"
last_modified_at: 2022-12-21 
toc: true
---

### Logical signals

The fundamental signal building block in ROHD is called [`Logic`](https://intel.github.io/rohd/rohd/Logic-class.html).

```dart
// a one bit, unnamed signal
var x = Logic();

// an 8-bit bus named 'b'
var bus = Logic(name: 'b', width: 8)
```

#### The value of a signal

You can access the current value of a signal using `value`.  You cannot access this as part of synthesizable ROHD code.  ROHD supports X and Z values and propogation.  If the signal is valid (no X or Z in it), you can also convert it to an `int` with `value.toInt()` (ROHD will throw an exception otherwise).  If the signal has more bits than a dart `int` (64 bits, usually), you need to use `value.toBigInt()` to get a `BigInt` (again, ROHD will throw an exception otherwise).

The value of a `Logic` is of type [`LogicValue`](https://intel.github.io/rohd/rohd/LogicValue-class.html), with pre-defined constant bit values `x`, `z`, `one`, and `zero`.  `LogicValue` has a number of built-in logical operations (like `&`, `|`, `^`, `+`, `-`, etc.).

```dart
var x = Logic(width:2);

// a LogicValue
x.value

// an int
x.value.toInt()

// a BigInt
x.value.toBigInt()

// constructing a LogicValue a handful of different ways
LogicValue.ofString('0101xz01');                      // 0b0101xz01
LogicValue.of([LogicValue.one, LogicValue.zero]);     // 0b10
[LogicValue.z, LogicValue.x].swizzle();               // 0bzx
LogicValue.ofInt(15, 4);                              // 0xf
```

You can create `LogicValue`s using a variety of constructors including `ofInt`, `ofBigInt`, `filled` (like '0, '1, 'x, etc. in SystemVerilog), and `of` (which takes any `Iterable<LogicValue>`).

#### Listening to and waiting for changes

You can trigger on changes of `Logic`s with some built in events.  ROHD uses dart synchronous [streams](https://dart.dev/tutorials/language/streams) for events.

There are three testbench-consumable streams built-in to ROHD `Logic`s: `changed`, `posedge`, and `negedge`.  You can use `listen` to trigger something every time the edge transitions.  Note that this is *not* synthesizable by ROHD and should not be confused with a synthesizable `always(@)` type of statement.  Event arguments passed to listeners are of type `LogicValueChanged`, which has information about the `previousValue` and `newValue`.

```dart
Logic mySignal;
...
mySignal.posedge.listen((args) {
  print('mySignal was ${args.previousValue} before,'
      ' but there was a positive edge and the new value'
      ' is ${args.newValue}');
});
```

You can also use helper getters `nextChanged`, `nextPosedge`, and `nextNegedge` which return `Future<LogicValueChanged>`.  You can think of these as similar to something like `@(posedge mySignal);` in SystemVerilog testbench code.  Again, these are not something that should be included in synthesizable ROHD hardware.

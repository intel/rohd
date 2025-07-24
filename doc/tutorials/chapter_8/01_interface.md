# Content

- [ROHD Interfaces](#rohd-interfaces)
- [Counter Module](#counter-module)
- [Counter Module Interface](#counter-module-interface)
- [Exercise](#exercise)

## Learning Outcome

In this chapter:

- You will learn how to use ROHD interface abstraction API to group and reuse port easily.

## ROHD Interfaces

Interfaces make it easier to define port connections of a module in a reusable way. An example of the counter re-implemented using interfaces is shown below.

`Interface` takes a generic parameter for direction type. This enables you to group signals so make adding them as inputs/outputs easier for different modules sharing this interface.

The `Logic.port` constructor makes interface port definitions a little cleaner by taking the width as a positional argument.

When connecting an `Interface` to a `Module`, you should always create a new instance of the `Interface` so you don't modify the one being passed in through the constructor. Modifying the same `Interface` as was passed would have negative consequences if multiple `Modules` were consuming the same `Interface`, and also breaks the rules for `Module` input and output connectivity.

The `connectIO` function under the hood calls `addInput` and `addOutput` directly on the `Module` and connects those `Module` ports to the correct ports on the `Interface`s.  Connection is based on signal names.  You can use the `uniquify` Function argument in `connectIO` to uniquify inputs and outputs in case you have multiple instances of the same `Interface` connected to your module.

`Module` has functions called `connectInterface` and `connectPairInterface` which conveniently call `connectIO` and `pairConnectIO` and return the "internal" copy of the interface to use within the `Module`.

## Counter Module

In ROHD, the [`Counter` module](../../../example/example.dart) reside in the example is one of the most basic example. Let us try to understand the counter module and see how we can modified it with ROHD interface instead.

In the `Counter` module, its take in inputs `enable`, `reset`, `clk` and output `val`.

On every positive edge of the clock, the value of `val` will be increment by 1 if enable `en` is set to true.

```dart
// Define a class Counter that extends ROHD's abstract Module class.
class Counter extends Module {
  // For convenience, map interesting outputs to short variable names for
  // consumers of this module.
  Logic get val => output('val');

  // This counter supports any width, determined at run-time.
  final int width;

  Counter(Logic en, Logic reset, Logic clk,
      {this.width = 8, super.name = 'counter'}) {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered
    // outputs.
    en = addInput('en', en);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);

    final val = addOutput('val', width: width);

    // A local signal named 'nextVal'.
    final nextVal = Logic(name: 'nextVal', width: width);

    // Assignment statement of nextVal to be val+1
    // ('<=' is the assignment operator).
    nextVal <= val + 1;

    // `Sequential` is like SystemVerilog's always_ff, in this case trigger on
    // the positive edge of clk.
    Sequential(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog
      // always blocks.
      If(reset, then: [
        // The '<' operator is a conditional assignment.
        val < 0
      ], orElse: [
        If(en, then: [val < nextVal])
      ])
    ]);
  }
}
```

## Counter Module Interface

Let us see how we can change the `ROHD` module to `Counter` interface. First, we can create a enum `CounterDirection` that have tags of `inward`, `outward` and `misc`. You can think of this as what is the category you want to group your ports. This category can be reuse between modules. `inward` port group all inputs port, `outward` group all outputs port and `misc` group all miscellanous port such as `clk`.

Then, we can create our interface `CounterInterface` that extends from parents `Interface<TagType>`. The `TagType` is the enum that we create earlier. Let create the getters to all ports for `Counter` to allows us to send signals to the interface.

Let start by creating a constructor `CounterInterface`. Inside the constructor, add `setPorts()` function to group our common port. `setPorts` have function signature of `void setPorts(List<Logic> ports, [List<CounterDirection>? tags])` which received a List of `Logic` and `tags`.

Hence, the `CounterInterface` will look something like this:

```dart
enum CounterDirection { inward, outward, misc }

/// A simple [Interface] for [Counter].
class CounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');
  Logic get clk => port('clk');

  final int width;
  CounterInterface({this.width = 8}) {
    setPorts([Logic.port('en'), Logic.port('reset')], [CounterDirection.inward]);

    setPorts([
      Logic.port('val', width),
    ], [
      CounterDirection.outward
    ]);

    setPorts([Logic.port('clk')], [CounterDirection.misc]);
  }
}
```

Next, we want to modify the `Counter` module constructor to receive the interface. Then, we **MUST** create a new instance of the interface to avoid modify the interface inside the constructor.

```dart
// create a new interface instance. Let make it a private variable.
late final CounterInterface _intf;
Counter(CounterInterface intf): super('counter') {}
```

Now, let use the `connectInterface` function. As mentioned [previously](#rohd-interfaces), this function called `addInput` and `addOutput` (via `connectIO`) that help us register the ports. Therefore, we can pass the `module`, `interface`, `inputTags`, and `outputTags` as the arguments of the `connectInterface` function.

```dart
Counter(CounterInterface intf) : super(name: 'counter') {
    _intf = connectInterface(intf,
          inputTags: {CounterDirection.inward, CounterDirection.misc},
          outputTags: {CounterDirection.outward});

    final nextVal = Logic(name: 'nextVal', width: intf.width);

    nextVal <= _intf.val + 1;

    Sequential(_intf.clk, [
      If.block([
        Iff(_intf.reset, [
          _intf.val < 0,
        ]),
        ElseIf(_intf.en, [
          _intf.val < nextVal,
        ])
      ]),
    ]);
}
```

Yup, that all you need to use the ROHD interface. Now, let see how to do simulation or pass value to perform test with interface module.

The only different here is instead of passing the `Logic` value through constructor, we are going to instantiate the interface object and perform assignment directly through the getter function we create earlier.

```dart
Future<void> main() async {
  // instantiate the counter interface
  final counterInterface = CounterInterface();

  // Assign SimpleClockGenerator to the clk through assesing the getter function
  counterInterface.clk <= SimpleClockGenerator(10).clk;

  final counter = Counter(counterInterface);
  await counter.build();

  // Inject value to en and reset through interface
  counterInterface.en.inject(0);
  counterInterface.reset.inject(1);

  print(counter.generateSynth());

  WaveDumper(counter,
      outputPath: 'doc/tutorials/chapter_8/counter_interface.vcd');
  Simulator.registerAction(25, () {
    counterInterface.en.put(1);
    counterInterface.reset.put(0);
  });

  Simulator.setMaxSimTime(100);

  await Simulator.run();
}
```

Thats it for the ROHD interface. By using interface, you code can be a lot cleaner and readable. Hope you enjoy the tutorials. You can find the executable version of code at [counter_interface.dart](./counter_interface.dart).

## Exercise

1. Serial Peripheral Interface (SPI)

Serial Peripheral Interface (SPI) is an interface bus commonly used to send data between microcontrollers and small peripherals such as shift registers, sensors, and SD cards. It uses separate clock and data lines, along with a select line to choose the device you wish to talk to.

Build a SPI using ROHD interface. You can use the shift register as the peripheral, you can just build the unit test for peripheral.

Answer to this exercise can be found at [answers/exercise_1_spi.dart](./answers/exercise_1_spi.dart)

---
title: "Interfaces"
permalink: /docs/interfaces/
excerpt: "Interfaces"
last_modified_at: 2022-12-06
toc: true
---

Interfaces make it easier to define port connections of a module in a reusable way.  An example of the counter re-implemented using interfaces is shown below.

[`Interface`](https://intel.github.io/rohd/rohd/Interface-class.html) takes a generic parameter for direction type.  This enables you to group signals so make adding them as inputs/outputs easier for different modules sharing this interface.

The [`Port`](https://intel.github.io/rohd/rohd/Port-class.html) class extends `Logic`, but has a constructor that takes width as a positional argument to make interface port definitions a little cleaner.

When connecting an `Interface` to a `Module`, you should always create a new instance of the `Interface` so you don't modify the one being passed in through the constructor.  Modifying the same `Interface` as was passed would have negative consequences if multiple `Module`s were consuming the same `Interface`, and also breaks the rules for `Module` input and output connectivity.

The `connectIO` function under the hood calls `addInput` and `addOutput` directly on the `Module` and connects those `Module` ports to the correct ports on the `Interface`s.  Connection is based on signal names.  You can use the `uniquify` Function argument in `connectIO` to uniquify inputs and outputs in case you have multiple instances of the same `Interface` connected to your module.  You can also use the `setPort` function to directly set individual ports on the `Interface` instead of via tagged set of ports.

```dart
// Define a set of legal directions for this interface, and pass as parameter to Interface
enum CounterDirection {IN, OUT}
class CounterInterface extends Interface<CounterDirection> {

  // include the getters in the interface so any user can access them
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');

  final int width;
  CounterInterface(this.width) {
    // register ports to a specific direction
    setPorts([
      Port('en'), // Port extends Logic
      Port('reset')
    ], [CounterDirection.IN]);  // inputs to the counter

    setPorts([
      Port('val', width),
    ], [CounterDirection.OUT]); // outputs from the counter
  }

}

class Counter extends Module {

  late final CounterInterface intf;
  Counter(CounterInterface intf) {
    // define a new interface, and connect it to the interface passed in
    this.intf = CounterInterface(intf.width)
      ..connectIO(this, intf,
        // map inputs and outputs to appropriate directions
        inputTags: {CounterDirection.IN},
        outputTags: {CounterDirection.OUT}
      );

    _buildLogic();
  }

  void _buildLogic() {
    var nextVal = Logic(name: 'nextVal', width: intf.width);

    // access signals directly from the interface
    nextVal <= intf.val + 1;

    Sequential( SimpleClockGenerator(10).clk, [
      If(intf.reset, then:[
        intf.val < 0
      ], orElse: [If(intf.en, then: [
        intf.val < nextVal
      ])])
    ]);
  }
}
```

## Pair Interfaces

A typical use case for interfaces is for two components to talk to each other, with some shared system inputs like clocks, resets, etc.  Additionally, interfaces may be broken down into sub-interfaces.  The `PairInterface` class can help automate a lot of the boilerplate for these types of common use cases.

A simple interface with a clock, request, and response might look like this:

```dart
class SimpleInterface extends PairInterface {
  Logic get clk => port('clk');
  Logic get req => port('req');
  Logic get rsp => port('rsp');

  SimpleInterface()
      : super(
          portsFromConsumer: [Port('rsp')],
          portsFromProducer: [Port('req')],
          sharedInputPorts: [Port('clk')],
        );

  SimpleInterface.clone(SimpleInterface super.otherInterface) : super.clone();
}
```

Note that it comes with helpers in the super constructor for grouping ports as well as cloning the interface.  Using this interface in a simple provider/consumer scenario, even with module hierarchy is easy.  You can use the `pairConnectIO` function which references the "role" of the component rather than listing input and output tags explicitly.

```dart
class SimpleProvider extends Module {
  late final SimpleInterface _intf;
  SimpleProvider(SimpleInterface intf) {
    _intf = SimpleInterface.clone(intf)
      ..pairConnectIO(this, intf, PairRole.provider);

    SimpleSubProvider(_intf);
  }
}

class SimpleSubProvider extends Module {
  late final SimpleInterface _intf;
  SimpleSubProvider(SimpleInterface intf) {
    _intf = SimpleInterface.clone(intf)
      ..pairConnectIO(this, intf, PairRole.provider);
  }
}

class SimpleConsumer extends Module {
  late final SimpleInterface _intf;
  SimpleConsumer(SimpleInterface intf) {
    _intf = SimpleInterface.clone(intf)
      ..pairConnectIO(this, intf, PairRole.consumer);
  }
}

class SimpleTop extends Module {
  SimpleTop(Logic clk) {
    clk = addInput('clk', clk);
    final intf = SimpleInterface();
    intf.clk <= clk;
    SimpleConsumer(intf);
    SimpleProvider(intf);
  }
}
```

You can easily add interface hierarchy with the `addSubInterface` function.  For example:

```dart
class SubInterface extends PairInterface {
  Logic get rsp => port('rsp');
  Logic get req => port('req');

  SubInterface()
      : super(
          portsFromConsumer: [Port('rsp')],
          portsFromProvider: [Port('req')],
        );
  SubInterface.clone(SubInterface super.otherInterface) : super.clone();
}

class TopLevelInterface extends PairInterface {
  Logic get clk => port('clk');

  final int numSubInterfaces;

  final List<SubInterface> subIntfs = [];

  TopLevelInterface(this.numSubInterfaces)
      : super(
          sharedInputPorts: [Port('clk')],
        ) {
    for (var i = 0; i < numSubInterfaces; i++) {
      subIntfs.add(addSubInterface('sub$i', SubInterface()));
    }
  }

  TopLevelInterface.clone(TopLevelInterface otherInterface)
      : this(otherInterface.numSubInterfaces);
}
```

There are some other utilities available in `PairInterface` as well, such as the ability to reverse sub-interfaces. Check out the API docs for full details.

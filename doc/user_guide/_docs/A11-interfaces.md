---
title: "Interfaces"
permalink: /docs/interfaces/
excerpt: "Interfaces"
last_modified_at: 2025-7-24
toc: true
---

Interfaces make it easier to define port connections of a module in a reusable way.  An example of the counter re-implemented using interfaces is shown below.

[`Interface`](https://intel.github.io/rohd/rohd/Interface-class.html) takes a generic parameter for direction type.  This enables you to group signals so make adding them as inputs/outputs easier for different modules sharing this interface.

The [`Logic.port`](https://intel.github.io/rohd/rohd/Logic-class.html) constructor makes interface port definitions a little cleaner by taking the width as a positional argument.

When connecting an `Interface` to a `Module`, you should always create a new instance of the `Interface` so you don't modify the one being passed in through the constructor.  Modifying the same `Interface` as was passed would have negative consequences if multiple `Module`s were consuming the same `Interface`, and also breaks the rules for `Module` input and output connectivity.

The `connectIO` function under the hood calls `addInput` and `addOutput` directly on the `Module` and connects those `Module` ports to the correct ports on the `Interface`s.  Connection is based on signal names.  You can use the `uniquify` Function argument in `connectIO` to uniquify inputs and outputs in case you have multiple instances of the same `Interface` connected to your module.

`Module` has functions called `addInterfacePorts` and `addPairInterfacePorts` which conveniently call `connectIO` and `pairConnectIO` and return the "internal" copy of the interface to use within the `Module`. For these to work, all `Interface`s must implement a `clone()` method so that an internal copy can be created.

```dart
// Define a set of legal directions for this interface, and pass as parameter to Interface
enum CounterDirection { inward, outward, misc }

class CounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');
  Logic get clk => port('clk');

  final int width;
  CounterInterface({this.width = 8}) {
    // register ports to a specific direction or group
    setPorts([
      Logic.port('en'), // Logic.port factory returns Logic
    ], [
      CounterDirection.inward // inputs to the counter
    ]);

    setPorts([
      Logic.port('val', width),
    ], [
      CounterDirection.outward // outputs from the counter
    ]);

    setPorts([
      Logic.port('clk'),
      Logic.port('reset'),
    ], [
      CounterDirection.misc // other miscellaneous ports
    ]);
  }

  @override
  CounterInterface clone() => CounterInterface(width: width);
}

class Counter extends Module {
  late final CounterInterface _intf;

  Counter(CounterInterface intf) : super(name: 'counter') {
    _intf = addInterfacePorts(intf,
        // map inputs and outputs to appropriate directions
        inputTags: {CounterDirection.inward, CounterDirection.misc},
        outputTags: {CounterDirection.outward});

    // access signals directly from the interface
    _intf.val <=
        flop(
          _intf.clk,
          reset: _intf.reset,
          (_intf.val + 1).named('nextVal'),
        );
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
          portsFromConsumer: [Logic.port('rsp')],
          portsFromProvider: [Logic.port('req')],
          sharedInputPorts: [Logic.port('clk')],
        );

  SimpleInterface.clone(SimpleInterface super.otherInterface) : super.clone();
}
```

Note that it comes with helpers in the super constructor for grouping ports as well as cloning the interface.  Using this interface in a simple provider/consumer scenario, even with module hierarchy is easy.  You can use the `pairConnectIO` function which references the "role" of the component rather than listing input and output tags explicitly.

```dart
class SimpleProvider extends Module {
  late final SimpleInterface _intf;
  SimpleProvider(SimpleInterface intf) {
    _intf = addPairInterfacePorts(intf, PairRole.provider);

    SimpleSubProvider(_intf);
  }
}

class SimpleSubProvider extends Module {
  late final SimpleInterface _intf;
  SimpleSubProvider(SimpleInterface intf) {
    _intf = addPairInterfacePorts(intf, PairRole.provider);
  }
}

class SimpleConsumer extends Module {
  late final SimpleInterface _intf;
  SimpleConsumer(SimpleInterface intf) {
    _intf = addPairInterfacePorts(intf, PairRole.consumer);
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
          portsFromConsumer: [Logic.port('rsp')],
          portsFromProvider: [Logic.port('req')],
        );
  SubInterface.clone(SubInterface super.otherInterface) : super.clone();
}

class TopLevelInterface extends PairInterface {
  Logic get clk => port('clk');

  final int numSubInterfaces;

  final List<SubInterface> subIntfs = [];

  TopLevelInterface(this.numSubInterfaces)
      : super(
          sharedInputPorts: [Logic.port('clk')],
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

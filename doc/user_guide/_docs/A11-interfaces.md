---
title: "Interfaces"
permalink: /docs/interfaces/
excerpt: "Interfaces"
last_modified_at: 2026-11-02
toc: true
---

Interfaces make it easier to define port connections of a module in a reusable way.  An example of the counter re-implemented using interfaces is shown below.

[`Interface`](https://intel.github.io/rohd/rohd/Interface-class.html) takes a generic parameter for direction type.  This enables you to group signals so make adding them as inputs/outputs easier for different modules sharing this interface.

The [`Logic.port`](https://intel.github.io/rohd/rohd/Logic-class.html) constructor makes interface port definitions a little cleaner by taking the width as a positional argument.

When connecting an `Interface` to a `Module`, you should always create a new instance of the `Interface` so you don't modify the one being passed in through the constructor.  Modifying the same `Interface` as was passed would have negative consequences if multiple `Module`s were consuming the same `Interface`, and also breaks the rules for `Module` input and output connectivity.

The `connectIO` function under the hood calls `addInput` and `addOutput` directly on the `Module` and connects those `Module` ports to the correct ports on the `Interface`s.  Connection is based on signal names.  You can use the `uniquify` Function argument in `connectIO` to uniquify inputs and outputs in case you have multiple instances of the same `Interface` connected to your module.

`Module` has functions called `addInterfacePorts` and `addPairInterfacePorts` which register an `Interface` (or `PairInterface` for a given `PairRole`) on the `Module` and return the "internal" copy of the interface to use within the `Module`. For these to work, all `Interface`s must implement a `clone()` method so that an internal copy can be created. Prefer these over calling `connectIO` or `pairConnectIO` directly so that module code does not depend on how interface ports are laid out.

When the internal interface should intentionally be a different object or type than a clone of the external one, use `addInterfaceFrom` or `addPairInterfaceFrom`, which register a provided target against the source and return that target.

For a type-safe provider/consumer boundary, split a `PairInterface` with
`intf.split()`. The returned `PairProvider` and `PairConsumer` wrappers can be
required by module constructors, and `addPairProviderPorts`,
`addPairConsumerPorts`, `addPairProviderFrom`, and `addPairConsumerFrom`
select the corresponding role without accepting an endpoint for the other role.
The existing role-based APIs remain available for compatibility and dynamic
role selection.

### Experimental structured interface ports

`addStructuredInterface` and `addStructuredPairInterface` are experimental
alternatives for module boundaries that consistently carry an interface in one
direction. Selected input and output fields are grouped into separate typed
`LogicStructure` ports when a direction has two or more fields. A direction
with exactly one field instead creates a direct
`<interface>_<field>` port, avoiding a one-field wrapper structure. InOut
fields retain individual net ports.

Pass `name:` to select the interface prefix, or use `uniquify:` to derive one.
The returned internal interface clone remains the module implementation API.
`structuredInterfacePortBindings` exposes the experimental, read-only
relationship between the external interface, internal clone, and actual
directional ports.

```dart
control = addStructuredInterface(
  control,
  name: 'control',
  inputTags: {CounterDirection.inward, CounterDirection.misc},
  outputTags: {CounterDirection.outward},
);
```

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

  @override
  SimpleInterface clone() => SimpleInterface();
}
```

Note that it comes with helpers in the super constructor for grouping ports as
well as cloning the interface. Split an interface once in its owning parent,
then require the appropriate endpoint type in each module constructor. This
prevents a provider endpoint from accidentally being supplied to a consumer
module.

```dart
class SimpleProvider extends Module {
  late final SimpleInterface _intf;
  SimpleProvider(PairProvider<SimpleInterface> endpoint) {
    _intf = addPairProviderPorts(endpoint);

    final (provider, _) = _intf.split();
    SimpleSubProvider(provider);
  }
}

class SimpleSubProvider extends Module {
  late final SimpleInterface _intf;
  SimpleSubProvider(PairProvider<SimpleInterface> endpoint) {
    _intf = addPairProviderPorts(endpoint);
  }
}

class SimpleConsumer extends Module {
  late final SimpleInterface _intf;
  SimpleConsumer(PairConsumer<SimpleInterface> endpoint) {
    _intf = addPairConsumerPorts(endpoint);
  }
}

class SimpleTop extends Module {
  SimpleTop(Logic clk) {
    clk = addInput('clk', clk);
    final intf = SimpleInterface();
    intf.clk <= clk;
    final (provider, consumer) = intf.split();
    SimpleConsumer(consumer);
    SimpleProvider(provider);
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

---
title: "Interfaces"
permalink: /docs/interfaces/
excerpt: "Interfaces"
last_modified_at: 2022-12-06
toc: true
---

### Interfaces

Interfaces make it easier to define port connections of a module in a reusable way.  An example of the counter re-implemented using interfaces is shown below.

[`Interface`]({{ site.baseurl }}api/rohd/Interface-class.html) takes a generic parameter for direction type.  This enables you to group signals so make adding them as inputs/outputs easier for different modules sharing this interface.

The [`Port`]({{ site.baseurl }}api/rohd/Port-class.html) class extends `Logic`, but has a constructor that takes width as a positional argument to make interface port definitions a little cleaner.

When connecting an `Interface` to a `Module`, you should always create a new instance of the `Interface` so you don't modify the one being passed in through the constructor.  Modifying the same `Interface` as was passed would have negative consequences if multiple `Module`s were consuming the same `Interface`, and also breaks the rules for `Module` input and output connectivity.

The `connectIO` function under the hood calls `addInput` and `addOutput` directly on the `Module` and connects those `Module` ports to the correct ports on the `Interface`s.  Connection is based on signal names.  You can use the `uniquify` Function argument in `connectIO` to uniquify inputs and outputs in case you have multiple instances of the same `Interface` connected to your module.  You can also use the `setPort` function to directly set individual ports on the `Interface` instead of via tagged set of ports.

```dart
// Define a set of legal directions for this interface, 
// and pass as parameter to Interface
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

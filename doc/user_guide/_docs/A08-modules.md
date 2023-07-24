---
title: "Modules"
permalink: /docs/modules/
excerpt: "Modules"
last_modified_at: 2022-12-06
toc: true
---

### Modules

[`Module`]({{ site.baseurl }}api/rohd/Module-class.html)s are similar to modules in SystemVerilog.  They have inputs and outputs and logic that connects them.  There are a handful of rules that *must* be followed when implementing a module.

1. All logic within a `Module` must consume only inputs (from the `input` or `addInput` methods) to the Module either directly or indirectly.
2. Any logic outside of a `Module` must consume the signals only via outputs (from the `output` or `addOutput` methods) of the Module.
3. Logic must be defined *before* the call to `super.build()`, which *always* must be called at the end of the `build()` method if it is overidden.

The reasons for these rules have to do with how ROHD is able to determine which logic and `Module`s exist within a given Module and how ROHD builds connectivity.  If these rules are not followed, generated outputs (including waveforms and SystemVerilog) may be unpredictable.

You should strive to build logic within the constructor of your `Module` (directly or via method calls within the constructor).  This way any code can utilize your `Module` immediately after creating it.  **Be careful** to consume the registered `input`s and drive the registered `output`s of your module, and not the "raw" parameters.

It is legal to put logic within an override of the `build` function, but that forces users of your module to always call `build` before it will be functionally usable for simple simulation.  If you put logic in `build()`, ensure you put the call to `super.build()` *at the end* of the method.

Note that the `build()` method returns a `Future<void>`, not just `void`.  This is because the `build()` method is permitted to consume real wallclock time in some cases, for example for setting up cosimulation with another simulator.  If you expect your build to consume wallclock time, make sure the `Simulator` is aware it needs to wait before proceeding.

It is not necessary to put all logic directly within a class that extends Module.  You can put synthesizable logic in other functions and classes, as long as the logic eventually connects to an input or output of a module if you hope to convert it to SystemVerilog.  Except where there is a desire for the waveforms and SystemVerilog generated to have module hierarchy, it is not necessary to use submodules within modules instead of plain classes or functions.

The `Module` base class has an optional String argument 'name' which is an instance name.

`Module`s have the below basic structure:

```dart
// class must extend Module to be a Module
class MyModule extends Module {
    
    // constructor
    MyModule(Logic in1, {String name='mymodule'}) : super(name: name) {
        // add inputs in the constructor, passing in the Logic it is connected to
        // it's a good idea to re-set the input parameters, 
        // so you don't accidentally use the wrong one
        in1 = addInput('in1', in1);

        // add outputs in the constructor as well
        // you can capture the output variable to a local variable for use
        var out = addOutput('out');

        // now you can define your logic
        // this example is just a passthrough from 'in1' to 'out'
        out <= in1;
    }
}
```

All gates or functionality apart from assign statements in ROHD are implemented using Modules.

#### Inputs, outputs, widths, and getters

The default width of an input and output is 1.  You can control the width of ports using the `width` argument of `addInput()` and `addOutput()`.  You may choose to set them to a static number, based on some other variable, or even dynamically based on the width of input parameters.  These functions also return the input/output signal.

It can be convenient to use dart getters for signal names so that accessing inputs and outputs of a module doesn't require calling `input()` and `output()` every time.  It also makes it easier to consume your module.

Below are some examples of inputs and outputs in a Module.

```dart
class MyModule extends Module {

    MyModule(Logic a, Logic b, Logic c, {int xWidth=5}) {
        
        // 'a' should always be width 4, throw an exception if its wrong
        if(a.width != 4) throw Exception('Width of a must be 4!');
        addInput('a', a, width: 4);

        // allow 'b' to always be any width, based on what's passed in
        addInput('b', b, width: b.width);

        // default width is 1, so 'c' is 1 bit
        // addInput returns the value of input('c'), if you want it
        var c_input = addInput('c', c)

        // set the width of 'x' based on the constructor argument
        addOutput('x', width: xWidth);

        // you can dynamically set the output width based on an input width, 
        // as well addOutput returns the value of output('y'), if you want it
        var y_output = addOutput('y', width: b.width);
    }

    // A verbose getter of the value of input 'a'
    Logic get a {
      return input('a');
    }
    
    // Dart shorthand makes getters less verbose, 
    // but the functionality is the same as above
    Logic get b => input('b');
    Logic get x => output('x');
    Logic get y => output('y');

    // it is not necessary to have all signals accessible through getters, 
    // here we omit 'c'

}
```

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=409325108)

[![Tests](https://github.com/intel/rohd/actions/workflows/general.yml/badge.svg?event=push)](https://github.com/intel/rohd/actions/workflows/general.yml)
[![API Docs](https://img.shields.io/badge/API%20Docs-generated-success)](https://intel.github.io/rohd/rohd/rohd-library.html)
[![Chat](https://img.shields.io/discord/1001179329411166267?label=Chat)](https://discord.gg/jubxF84yGw)
[![License](https://img.shields.io/badge/License-BSD--3-blue)](https://github.com/intel/rohd/blob/main/LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](https://github.com/intel/rohd/blob/main/CODE_OF_CONDUCT.md)

# Rapid Open Hardware Development (ROHD) Framework

## Describing Hardware in Dart with ROHD

ROHD (pronounced like "road") is a framework for describing and verifying hardware in the Dart programming language.  ROHD enables you to build and traverse a graph of connectivity between module objects using unrestricted software.

Features of ROHD include:

- Full power of the modern **Dart language** for hardware design and verification
- Makes **validation collateral** simpler to develop and debug.  The [ROHD Verification Framework](https://github.com/intel/rohd-vf) helps build well-structured testbenches.
- Develop **layers of abstraction** within a hardware design, making it more flexible and powerful
- Easy **IP integration** and **interfaces**; using an IP is as easy as an import.  Reduces tedious, redundant, and error prone aspects of integration
- **Simple and fast build**, free of complex build systems and EDA vendor tools
- Can use the excellent pub.dev **package manager** and all the packages it has to offer
- Built-in event-based **fast simulator** with **4-value** (0, 1, X, and Z) support and a **waveform dumper** to .vcd file format
- Conversion of modules to equivalent, human-readable, structurally similar **SystemVerilog** for integration or downstream tool consumption
- **Run-time dynamic** module port definitions (numbers, names, widths, etc.) and internal module logic, including recursive module contents
- Simple, free, **open source tool stack** without any headaches from library dependencies, file ordering, elaboration/analysis options, +defines, etc.
- Excellent, simple, fast **unit-testing** framework
- **Less verbose** than alternatives (fewer lines of code)
- Enables **higher quality** development
- Replaces hacky perl/python scripting for automation with powerful **native control of design generation**
- Fewer bugs and lines of code means **shorter development schedule**
- Support for **cosimulation with verilog modules** (via [ROHD Cosim](https://github.com/intel/rohd-cosim)) and **instantiation of verilog modules** in generated SystemVerilog code
- Use **modern IDEs** like Visual Studio Code, with excellent static analysis, fast autocomplete, built-in debugger, linting, git integration, extensions, and much more
- Simulate with **various abstraction levels of models** from architectural, to functional, to cycle-accurate, to RTL levels in the same language and environment.

ROHD is *not* a new language, it is *not* a hardware description language (HDL), and it is *not* a version of High-Level Synthesis (HLS).  ROHD can be classified as a generator framework.

You can think of this project as an attempt to *replace* SystemVerilog and related build systems as the front-end methodology of choice in the industry.

One of ROHD's goals is to help grow an open-source community around reusable hardware designs and verification components.

## Why Dart?

Dart is a modern, relatively new language developed by Google.  It is designed with client-side application development in mind (e.g. apps and websites), but also has great performance for general tasks.  It adopts some of the most loved syntax and features from languages like C++, Java, C#, JavaScript/TypeScript, and Kotlin.  Dart is extremely user-friendly, fun to use, and **easy to learn**.  The excellent, fast static analysis with a modern IDE with autocomplete makes it easy to learn as you work.  Dart has a lot of great modern language features, including null safety.

Because it is designed with asynchronous requests in mind (i.e. sending a request to a server and not freezing the application while it waits for a response), Dart has async/await and `Future`s built in, with concurrent programming using *isolates*.  These constructs enable code to execute in parallel without multithreading.  These chacteristics make modelling hardware very easy.

Dart can compile to native machine code, but also includes its own high-performance VM and a JIT compiler.  During development, you can use a feature called "hot reload" to change code while the program is actively executing.

Dart has an excellent package manager called "pub" (<https://pub.dev>).  It is possible to host a private Dart Pub server for packages that shouldn't be shared broadly (e.g. Top-Secret IP).

### The Challenge of Justifying Trying a New Language

[This StackOverflow answer](https://stackoverflow.com/questions/53007782/what-benefits-does-chisel-offer-over-classic-hardware-description-languages) about why it's worth trying Chisel (an alternative to ROHD) contains valuable insight into why it is difficult in general to justify a new language to someone who hasn't used it before:

> Language *power* is notoriously difficult to objectively evaluate. Paul Graham describes this as the "Blub Paradox" in his ["Beating the Averages" essay](http://www.paulgraham.com/avg.html). Graham's thesis is that an engineer proficient in a less powerful language cannot evaluate the utility of a more powerful language.

If you're thinking "SystemVerilog is just fine, I don't need something new", it is worth reading either or both of the StackOverflow answer and the Paul Graham essay.

### More Information on Dart

Try out Dart instantly from your browser here (it supports ROHD too!): <https://dartpad.dev/?null_safety=true>

See some Dart language samples here: <https://dart.dev/samples>

For more information on Dart and tutorials, see <https://dart.dev/> and <https://dart.dev/overview>

## Development Recommendations

- The [ROHD Verification Framework](https://github.com/intel/rohd-vf) is a UVM-like framework for building testbenches for hardware modelled in ROHD.
- The [ROHD Cosimulation](https://github.com/intel/rohd-cosim) package allows you to cosimulate the ROHD simulator with a variety of SystemVerilog simulators.
- Visual Studio Code (vscode) is a great, free IDE with excellent support for Dart.  It works well on all platforms, including native Windows or Windows Subsystem for Linux (WSL) which allows you to run a native Linux kernel (e.g. Ubuntu) within Windows.  You can also use vscode to develop on a remote machine with the Remote SSH extension.
  - vscode: <https://code.visualstudio.com/>
  - WSL: <https://docs.microsoft.com/en-us/windows/wsl/install-win10>
  - Remote SSH: <https://code.visualstudio.com/blogs/2019/07/25/remote-ssh>
  - Dart extension for vscode: <https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code>

## Getting started

Once you have Dart installed, if you don't already have a project, you can create one using `dart create`: <https://dart.dev/tools/dart-tool>

Then add ROHD as a dependency to your pubspec.yaml file.  ROHD is [registered](https://pub.dev/packages/rohd) on pub.dev.  The easiest way to add ROHD as a dependency is following the instructions here <https://pub.dev/packages/rohd/install>.

Now you can import it in your project using:

```dart
import 'package:rohd/rohd.dart';
```

There are complete API docs available at <https://intel.github.io/rohd/rohd/rohd-library.html>.

If you need some help, you can join the [Discord server](https://discord.com/invite/jubxF84yGw) or visit our [Discussions](https://github.com/intel/rohd/discussions) page.  These are friendly places where you can ask questions, share ideas, or just discuss openly!  You could also head to [StackOverflow.com](https://stackoverflow.com/) (use the tag `rohd`) to ask questions or look for answers.

You also may be interested to join the [ROHD Forum](https://github.com/intel/rohd/wiki/ROHD-Forum) periodic meetings with other users and developers in the ROHD community.  The meetings are open to anyone interested!

Be sure to note the minimum Dart version required for ROHD specified in pubspec.yaml (at least 2.14.0).  If you're using the version of Dart that came with Flutter, it might be older than that.

## Package Managers for Hardware

In the Dart ecosystem, you can use a package manager to define all package dependencies.  A package manager allows you to define constrainted subsets of versions of all your *direct* dependencies, and then the tool will solve for a coherent set of all (direct and indirect) dependencies required to build your project.  There's no need to manually figure out tool versions, build flags and options, environment setup, etc. because it is all guaranteed to work.  Integration of other packages (whether a tool or a hardware IP) become as simple as an `import` statment.  Compare that to SystemVerilog IP integration!

Read more about package managers here: <https://en.wikipedia.org/wiki/Package_manager>
Take a look at Dart's package manager, pub.dev, here: <https://pub.dev>

## ROHD Syntax and Examples

The below subsections offer some examples of implementations and syntax in ROHD.

### A full example of a counter module

To get a quick feel for what ROHD looks like, below is an example of what a simple counter module looks like in ROHD.

```dart
// Import the ROHD package
import 'package:rohd/rohd.dart';

// Define a class Counter that extends ROHD's abstract Module class
class Counter extends Module {

  // For convenience, map interesting outputs to short variable names for consumers of this module
  Logic get val => output('val');

  // This counter supports any width, determined at run-time
  final int width;
  Counter(Logic en, Logic reset, Logic clk, {this.width=8, String name='counter'}) : super(name: name) {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered outputs.
    en    = addInput('en', en);
    reset = addInput('reset', reset);
    clk   = addInput('clk', clk);

    var val = addOutput('val', width: width);

    // A local signal named 'nextVal'
    var nextVal = Logic(name: 'nextVal', width: width);

    // Assignment statement of nextVal to be val+1 (<= is the assignment operator)
    nextVal <= val + 1;

    // `Sequential` is like SystemVerilog's always_ff, in this case trigger on the positive edge of clk
    Sequential(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog always blocks
      If(reset, then:[
        // the '<' operator is a conditional assignment
        val < 0
      ], orElse: [If(en, then: [
        val < nextVal
      ])])
    ]);
  }
}

```

You can find an executable version of this counter example in [example/example.dart](https://github.com/intel/rohd/blob/main/example/example.dart).

### A more complex example

See a more advanced example of a logarithmic-depth tree of arbitrary functionality at [doc/TreeExample.md](https://github.com/intel/rohd/blob/main/doc/TreeExample.md).

You can find an executable version of the tree example in [example/tree.dart](https://github.com/intel/rohd/blob/main/example/tree.dart).

### Logical signals

The fundamental signal building block in ROHD is called [`Logic`](https://intel.github.io/rohd/rohd/Logic-class.html).

```dart
// a one bit, unnamed signal
var x = Logic();

// an 8-bit bus named 'b'
var bus = Logic(name: 'b', width: 8)
```

#### The value of a signal

You can access the current value of a signal using `value`.  You cannot access this as part of synthesizable ROHD code.  ROHD supports X and Z values and propogation.  If the signal is valid (no X or Z in it), you can also convert it to an int with `value.toInt()` (ROHD will throw an exception otherwise).  If the signal has more bits than a dart `int` (64 bits, usually), you need to use `value.toBigInt()` to get a `BigInt` (again, ROHD will throw an exception otherwise).

The value of a `Logic` is of type [`LogicValue`](https://intel.github.io/rohd/rohd/LogicValue-class.html), with pre-defined constant bit values `x`, `z`, `one`, and `zero`.  `LogicValue` has a number of built-in logical operations (like &, |, ^, +, -, etc.).

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
  print("mySignal was ${args.previousValue} before, but there was a positive edge and the new value is ${args.newValue}");
});
```

You can also use helper getters `nextChanged`, `nextPosedge`, and `nextNegedge` which return `Future<LogicValueChanged>`.  You can think of these as similar to something like `@(posedge mySignal);` in SystemVerilog testbench code.  Again, these are not something that should be included in synthesizable ROHD hardware.

### Constants

Constants can often be inferred by ROHD automatically, but can also be explicitly defined using [`Const`](https://intel.github.io/rohd/rohd/Const-class.html), which extends `Logic`.

```dart
// a 16 bit constant with value 5
var x = Const(5, width:16);
```

There is a convenience function for converting binary to an integer:

```dart
// this is equvialent to and shorter than int.parse('010101', radix:2)
// you can put underscores to help with readability, they are ignored
bin('01_0101')
```

### Assignment

To assign one signal to the value of another signal, use the `<=` operator.  This is a hardware synthesizable assignment connecting two wires together.

```dart
var a = Logic(), b = Logic();
// assign a to always have the same value as b
a <= b;
```

### Simple logical, mathematical, and comparison operations

Logical operations on signals are very similar to those in SystemVerilog.

```dart
a_bar     <=  ~a;      // not
a_and_b   <=  a & b;   // and
a_or_b    <=  a | b;   // or
a_xor_b   <=  a ^ b;   // xor
and_a     <=  a.and(); // unary and
or_a      <=  a.or();  // unary or
xor_a     <=  a.xor(); // unary xor
a_plus_b  <=  a + b;   // addition
a_sub_b   <=  a - b;   // subtraction
a_times_b <=  a * b;   // multiplication
a_div_b   <=  a / b;   // division
a_mod_b   <=  a % b;   // modulo
a_eq_b    <=  a.eq(b)  // equality              NOTE: == is for Object equality of Logic's
a_lt_b    <=  a.lt(b)  // less than             NOTE: <  is for conditional assignment
a_lte_b   <=  a.lte(b) // less than or equal    NOTE: <= is for assignment
a_gt_b    <=  (a > b)  // greater than          NOTE: careful with order of operations, > needs parentheses in this case
a_gte_b   <=  (a >= b) // greater than or equal NOTE: careful with order of operations, >= needs parentheses in this case
answer    <=  mux(selectA, a, b) // answer = selectA ? a : b
```

### Shift Operations

Dart has [implemented the triple shift](https://github.com/dart-lang/language/blob/master/accepted/2.14/triple-shift-operator/feature-specification.md) operator (>>>) in the opposite way as is [implemented in SystemVerilog](https://www.nandland.com/verilog/examples/example-shift-operator-verilog.html).  That is to say in Dart, >>> means *logical* shift right (fill with 0's), and >> means *arithmetic* shift right (maintaining sign).  ROHD keeps consistency with Dart's implementation to avoid introducing confusion within Dart code you write (whether ROHD or plain Dart).

```dart
a << b    // logical shift left
a >> b    // arithmetic shift right
a >>> b   // logical shift right
```

### Bus ranges and swizzling

Multi-bit busses can be accessed by single bits and ranges or composed from multiple other signals.  Slicing, swizzling, etc. are also accessible on `LogicValue`s.

```dart
var a = Logic(width:8),
    b = Logic(width:3),
    c = Const(7, width:5),
    d = Logic(),
    e = Logic(width: 9);


// assign b to the bottom 3 bits of a
b <= a.slice(2,0);

// assign d to the top bit of a
d <= a[7];

// construct e by swizzling bits from b, c, and d
// here, the MSB is on the left, LSB is on the right
e <= [d, c, b].swizzle();

// alternatively, do a reverse swizzle (useful for lists where 0-index is actually the 0th element)
// here, the LSB is on the left, the MSB is on the right
e <= [b, c, d].rswizzle();
```

ROHD does not support assignment to a subset of a bus.  That is, you *cannot* do something like `e[3] <= d`.  Instead, you can use the `withSet` function to get a copy with that subset of the bus assigned to something else.  This applies for both `Logic` and `LogicValue`.  For example:

```dart
// reassign the variable `e` to a new `Logic` where bit 3 is set to `d`
e = e.withSet(3, d);
```

### Modules

[`Module`](https://intel.github.io/rohd/rohd/Module-class.html)s are similar to modules in SystemVerilog.  They have inputs and outputs and logic that connects them.  There are a handful of rules that *must* be followed when implementing a module.

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
        // it's a good idea to re-set the input parameters so you don't accidentally use the wrong one
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

        // you can dynamically set the output width based on an input width, as well
        // addOutput returns the value of output('y'), if you want it
        var y_output = addOutput('y', width: b.width);
    }

    // A verbose getter of the value of input 'a'
    Logic get a {
      return input('a');
    }

    // Dart shorthand makes getters less verbose, but the functionality is the same as above
    Logic get b => input('b');
    Logic get x => output('x');
    Logic get y => output('y');

    // it is not necessary to have all signals accessible through getters, here we omit 'c'

}
```

### Sequentials

ROHD has a basic [`FlipFlop`](https://intel.github.io/rohd/rohd/FlipFlop-class.html) module that can be used as a flip flop.  For more complex sequential logic, use the `Sequential` block described in the Conditionals section.

Dart doesn't have a notion of certain signals being "clocks" vs. "not clocks".  You can use any signal as a clock input to sequential logic, and have as many clocks of as many frequencies as you want.

### Conditionals

ROHD supports a variety of [`Conditional`](https://intel.github.io/rohd/rohd/Conditional-class.html) type statements that always must fall within a type of `_Always` block, similar to SystemVerilog.  There are two types of `_Always` blocks: [`Sequential`](https://intel.github.io/rohd/rohd/Sequential-class.html) and [`Combinational`](https://intel.github.io/rohd/rohd/Combinational-class.html), which map to SystemVerilog's `always_ff` and `always_comb`, respectively.  `Combinational` takes a list of `Conditional` statements.  Different kinds of `Conditional` statement, such as `If`, may be composed of more `Conditional` statements.  You can create `Conditional` composition chains as deep as you like.

Conditional statements are executed imperatively and in order, just like the contents of `always` blocks in SystemVerilog.  `_Always` blocks in ROHD map 1-to-1 with SystemVerilog `always` statements when converted.

Assignments within an `_Always` should be executed conditionally, so use the `<` operator which creates a [`ConditionalAssign`](https://intel.github.io/rohd/rohd/ConditionalAssign-class.html) object instead of `<=`.  The right hand side a `ConditionalAssign` can be anything that can be `put` onto a `Logic`, which includes `int`s.  If you're looking to fill the width of something, use `Const` with the `fill = true`.

#### `If`

Below is an example of an [`If`](https://intel.github.io/rohd/rohd/If-class.html) statement in ROHD:

```dart
Combinational([
  If(a, then: [
      y < a,
      z < b,
      x < a & b,
      q < d,
  ], orElse: [ If(b, then: [
      y < b,
      z < a,
      q < 13,
  ], orElse: [
      y < 0,
      z < Const(1, width: 4, fill: true),
  ])])
]);
```

#### `IfBlock`

The [`IfBlock`](https://intel.github.io/rohd/rohd/IfBlock-class.html) makes syntax for long chains of if / else if / else chains nicer.  For example:

```dart
Sequential(clk, [
  IfBlock([
    // the first one must be Iff (yes, with 2 f's, to differentiate from If above)
    Iff(a & ~b, [
      c < 1,
      d < 0
    ]),
    ElseIf(b & ~a, [
      c < 1,
      d < 0
    ]),
    // have as many ElseIf's here as you want
    Else([
      c < 0,
      d < 1
    ])
  ])
]);
```

#### `Case` and `CaseZ`

ROHD supports [`Case`](https://intel.github.io/rohd/rohd/Case-class.html) and [`CaseZ`](https://intel.github.io/rohd/rohd/CaseZ-class.html) statements, including priority and unique flavors, which are implemented in the same way as SystemVerilog.  For example:

```dart
Combinational([
  Case([b,a].swizzle(), [
      CaseItem(Const(LogicValue.ofString('01')), [
        c < 1,
        d < 0
      ]),
      CaseItem(Const(LogicValue.ofString('10')), [
        c < 1,
        d < 0,
      ]),
    ], defaultItem: [
      c < 0,
      d < 1,
    ],
    conditionalType: ConditionalType.Unique
  ),
  CaseZ([b,a].swizzle(),[
      CaseItem(Const(LogicValue.ofString('z1')), [
        e < 1,
      ])
    ], defaultItem: [
      e < 0,
    ],
    conditionalType: ConditionalType.Priority
  )
]);
```

Note that ROHD supports the 'z' syntax, not the '?' syntax (these are equivalent in SystemVerilog).

There is no support for an equivalent of `casex` from SystemVerilog, since it can easily cause unsynthesizeable code to be generated (see: <https://www.verilogpro.com/verilog-case-casez-casex/>).

### Interfaces

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

### Non-synthesizable signal deposition

For testbench code or other non-synthesizable code, you can use `put` or `inject` on any `Logic` to deposit a value on the signal.  The two functions have similar behavior, but `inject` is shorthand for calling `put` inside of `Simulator.injectAction`, which allows the deposited change to propogate within the same `Simulator` tick.  Generally, you will want to use `inject` for testbench interaction with a design.

```dart
var a = Logic(), b = Logic(width:4);

// you can put an int directly on a signal
a.put(0);
b.inject(0xf);

// you can also put a `LogicValue` onto a signal
a.inject(LogicValue.x);
```

Note: changing a value directly with `put()` will propogate the value, but it will not trigger flip-flop edge detection or cosim interaction.

### Custom module behavior with custom in-line SystemVerilog representation

Many of the basic built-in gates in Dart implement custom behavior.  An implementation of the NotGate is shown below as an example.  There is different syntax for functions which can be inlined versus those which cannot (the ~ can be inlined).  In this case, the `InlineSystemVerilog` mixin is used, but if it were not inlineable, you could use `CustomSystemVerilog`.  Note that it is mandatory to provide an initial value computation when the module is first created for non-sequential modules.

```dart
/// A gate [Module] that performs bit-wise inversion.
class NotGate extends Module with InlineSystemVerilog {
  /// Name for the input of this inverter.
  late final String _inName;

  /// Name for the output of this inverter.
  late final String _outName;

  /// The input to this [NotGate].
  Logic get _in => input(_inName);

  /// The output of this [NotGate].
  Logic get out => output(_outName);

  /// Constructs a [NotGate] with [in_] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic in_, {super.name = 'not'}) {
    _inName = Module.unpreferredName(in_.name);
    _outName = Module.unpreferredName('${in_.name}_b');
    addInput(_inName, in_, width: in_.width);
    addOutput(_outName, width: in_.width);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(~_in.value);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }
    final a = inputs[_inName]!;
    return '~$a';
  }
}
```

### Pipelines

ROHD has a built-in syntax for handling pipelines in a simple & refactorable way.  The below example shows a three-stage pipeline which adds 1 three times.  Note that [`Pipeline`](https://intel.github.io/rohd/rohd/Pipeline-class.html) consumes a clock and a list of stages, which are each a `List<Conditional> Function(PipelineStageInfo p)`, where `PipelineStageInfo` has information on the value of a given signal in that stage.  The `List<Conditional>` the same type of procedural code that can be placed in `Combinational`.

```dart
Logic a;
var pipeline = Pipeline(clk,
  stages: [
    (p) => [
      // the first time `get` is called, `a` is automatically pipelined
      p.get(a) < p.get(a) + 1
    ],
    (p) => [
      p.get(a) < p.get(a) + 1
    ],
    (p) => [
      p.get(a) < p.get(a) + 1
    ],
  ]
);
var b = pipeline.get(a); // the output of the pipeline
```

This pipeline is very easy to refactor.  If we wanted to merge the last two stages, we could simply rewrite it as:

```dart
Logic a;
var pipeline = Pipeline(clk,
  stages: [
    (p) => [
      p.get(a) < p.get(a) + 1
    ],
    (p) => [
      p.get(a) < p.get(a) + 1,
      p.get(a) < p.get(a) + 1
    ],
  ]
);
var b = pipeline.get(a);
```

You can also optionally add stalls and reset values for signals in the pipeline.  Any signal not accessed via the `PipelineStageInfo` object is just accessed as normal, so other logic can optionally sit outside of the pipeline object.

ROHD also includes a version of `Pipeline` that supports a ready/valid protocol called [`ReadyValidPipeline`](https://intel.github.io/rohd/rohd/ReadyValidPipeline-class.html).  The syntax looks the same, but has some additional parameters for readys and valids.

### Finite State Machines

ROHD has a built-in syntax for handling FSMs in a simple & refactorable way.  The below example shows a 2 way Traffic light FSM.  Note that `StateMachine` consumes the `clk` and `reset` signals. Also accepts the reset state to transition to `resetState` along with the `List` of `states` of the FSM.

```dart
class TrafficTestModule extends Module {
  TrafficTestModule(Logic traffic, Logic reset) {
    traffic = addInput('traffic', traffic, width: traffic.width);
    var northLight = addOutput('northLight', width: traffic.width);
    var eastLight = addOutput('eastLight', width: traffic.width);
    var clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    var states = [
      State<LightStates>(LightStates.northFlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.northTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.northSlowing,
        traffic.eq(Direction.both()): LightStates.northSlowing,
      }, actions: [
        northLight < LightColor.green(),
        eastLight < LightColor.red(),
      ]),
      State<LightStates>(LightStates.northSlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.northTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.both()): LightStates.eastFlowing,
      }, actions: [
        northLight < LightColor.yellow(),
        eastLight < LightColor.red(),
      ]),
      State<LightStates>(LightStates.eastFlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.eastSlowing,
        traffic.eq(Direction.northTraffic()): LightStates.eastSlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.both()): LightStates.eastSlowing,
      }, actions: [
        northLight < LightColor.red(),
        eastLight < LightColor.green(),
      ]),
      State<LightStates>(LightStates.eastSlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.northTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.both()): LightStates.northFlowing,
      }, actions: [
        northLight < LightColor.red(),
        eastLight < LightColor.yellow(),
      ]),
    ];
    StateMachine<LightStates>(clk, reset, LightStates.northFlowing, states);
  }
}
```

## ROHD Simulator

The ROHD simulator is a static class accessible as [`Simulator`](https://intel.github.io/rohd/rohd/Simulator-class.html) which implements a simple event-based simulator.  All `Logic`s in Dart have `glitch` events which propogate values to connected `Logic`s downstream.  In this way, ROHD propogates values across the entire graph representation of the hardware (without any `Simulator` involvement required).  The simulator has a concept of (unitless) time, and arbitrary Dart functions can be registered to occur at arbitraty times in the simulator.  Asking the simulator to run causes it to iterate through all registered timestamps and execute the functions in chronological order.  When these functions deposit signals on `Logic`s, it propogates values across the hardware.  The simulator has a number of events surrounding execution of a timestamp tick so that things like `FlipFlop`s can know when clocks and signals are glitch-free.

- To register a function at an arbitraty timestamp, use `Simulator.registerAction`
- To set a maximum simulation time, use `Simulator.setMaxSimTime`
- To immediately end the simulation at the end of the current timestamp, use `Simulator.endSimulation`
- To run just the next timestamp, use `Simulator.tick`
- To run simulator ticks until completion, use `Simulator.run`
- To reset the simulator, use `Simulator.reset`
  - Note that this only resets the `Simulator` and not any `Module`s or `Logic` values
- To add an action to the Simulator in the *current* timestep, use `Simulator.injectAction`.

## Instantiation of External Modules

ROHD can instantiate external SystemVerilog modules.  The [`ExternalSystemVerilogModule`](https://intel.github.io/rohd/rohd/ExternalSystemVerilogModule-class.html) constructor requires the top level SystemVerilog module name.  When ROHD generates SystemVerilog for a model containing an `ExternalSystemVerilogModule`, it will instantiate instances of the specified `definitionName`.  This is useful for integration related activities.

The [ROHD Cosim](https://github.com/intel/rohd-cosim) package enables SystemVerilog cosimulation with ROHD by adding cosimulation capabilities to an `ExternalSystemVerilogModule`.

## Unit Testing

Dart has a great unit testing package available on pub.dev: <https://pub.dev/packages/test>

The ROHD package has a great set of examples of how to write unit tests for ROHD `Module`s in the test/ directory.

Note that when unit testing with ROHD, it is important to reset the `Simulator` with `Simulator.reset()`.

## Contributing

ROHD is under active development.  If you're interested in contributing, have feedback or a question, or found a bug, please see [CONTRIBUTING.md](https://github.com/intel/rohd/blob/main/CONTRIBUTING.md).

## Comparison with Alternatives

There are a lot of options for developing hardware.  This section briefly discusses popular alternatives to ROHD and some of their strengths and weaknesses.

### SystemVerilog

SystemVerilog is the most popular HDL (hardware descriptive language).  It is based on Verilog, with additional software-like constructs added on top of it.  Some major drawbacks of SystemVerilog are:

- SystemVerilog is old, verbose, and limited, which makes code more bug-prone
- Integration of IPs at SOC level with SystemVerilog is very difficult and time-consuming.
- Validation collateral is hard to develop, debug, share, and reuse when it is written in SystemVerilog.
- Building requires building packages with proper `include ordering based on dependencies, ordering of files read by compilers in .f files, correctly specifiying order of package and library dependencies, and correct analysis and elaboration options.  This is an area that drains many engineers' time debugging.
- Build and simulation are dependent on expensive EDA vendor tools or incomplete open-source alternatives.  Every tool has its own intricacies, dependencies, licensing, switches, etc. and different tools may synthesize or simulate the same code in a functionally inequivalent way.
- Designing configurable and flexible modules in pure SystemVerilog usually requires parameterization, compile-time defines, and "generate" blocks, which can be challenging to use, difficult to debug, and restrictive on approaches.
  - People often rely on perl scripts to bridge the gap for iteratively generating more complex hardware or stitching together large numbers of modules.
- Testbenches are, at the end of the day, software.  SystemVerilog is arguably a terrible programming language, since it is primarily focused at hardware description, which makes developing testbenches excessively challenging.  Basic software quality-of-life features are missing in SystemVerilog.
  - Mitigating the problem by connecting to other languages through DPI calls (e.g. C++ or SystemC) has it's own complexities with extra header files, difficulty modelling parallel execution and edge events, passing callbacks, etc.
  - UVM throws macros and boilerplate at the problem, which doesn't resolve the underlying limitations.

ROHD aims to enable all the best parts of SystemVerilog, while completely eliminating each of the above issues.  Build is automatic and part of Dart, packages and files can just be imported as needed, no vendor tools are required, hardware can be constructed using all available software constructs, and Dart is a fully-featured modern software language with modern features.

You can read more about SystemVerilog here: <https://en.wikipedia.org/wiki/SystemVerilog>

### Chisel

Chisel is a domain specific language (DSL) built on top of [Scala](https://www.scala-lang.org/), which is built on top of the Java virtual machine (JVM).  The goals of Chisel are somewhat aligned with the goals of ROHD.  Chisel can also convert to SystemVerilog.

- The syntax of Scala (and thus Chisel) is probably less familiar-feeling to most hardware engineers, and it can be more verbose than ROHD with Dart.
- Scala and the JVM are arguably less user friendly to debug than Dart code.
- Chisel is focused mostly on the hardware *designer* rather than the *validator*.  Many of the design choices for the language are centered around making it easier to parameterize and synthesize logic.  ROHD was created with validators in mind.
- Chisel generates logic that's closer to a netlist than what a similar implementation in SystemVerilog would look like.  This can make it difficult to debug or validate generated code.  ROHD generates structurally similar SystemVerilog that looks close to how you might write it.

Read more about Chisel here: <https://www.chisel-lang.org/>

### MyHDL (Python)

There have been a number of attempts to create a HDL on top of Python, but it appears the MyHDL is one of the most mature options.  MyHDL has many similar goals to ROHD, but chose to develop in Python instead of Dart.  MyHDL can also convert to SystemVerilog.

- MyHDL uses "generators" and decorators to help model concurrent behavior of hardware, which is arguably less user-friendly and intuitive than async/await and event based simulation in ROHD.
- While Python is a great programming langauge for the right purposes, some language features of Dart make it better for representing hardware.  Above is already mentioned Dart's isolates and async/await, which don't exist in the same way in Python.  Dart is statically typed with null safety while Python is dynamically typed, which can make static analysis (including intellisense, type safety, etc.) more challenging in Python.  Python can also be challenging to scale to large programs without careful architecting.
- Python is inherently slower to execute than Dart.
- MyHDL has support for cosimulation via VPI calls to SystemVerilog simulators.

Read more about MyHDL here: <http://www.myhdl.org/>

### High-Level Synthesis (HLS)

High-Level Synthesis (HLS) uses a subset of C++ and SystemC to describe algorithms and functionality, which EDA vendor tools can compile into SystemVerilog.  The real strength of HLS is that it enables design exploration to optimize a higher-level functional intent for area, power, and/or performance through proper staging and knowledge of the characteristics of the targeted process.

- HLS is a step above/away from RTL-level modelling, which is a strength in some situations but might not be the right level in others.
- HLS uses C++/SystemC, which is arguably a less "friendly" language to use than Dart.

Read more about one example of an HLS tool (Cadence's Stratus tool) here: <https://www.cadence.com/en_US/home/tools/digital-design-and-signoff/synthesis/stratus-high-level-synthesis.html>

There are a number of other attempts to make HLS better, including [XLS](https://github.com/google/xls) and [Dahlia](https://capra.cs.cornell.edu/dahlia/) & [Calyx](https://capra.cs.cornell.edu/calyx/).  There are discussions on ways to reasonably incorporate some of the strengths of HLS approaches into ROHD.

### Transaction Level Verilog (TL-Verilog)

Transaction Level Verilog (TL-Verilog) is like an extension on top of SystemVerilog that makes pipelining simpler and more concise.

- TL-Verilog makes RTL design easier, but doesn't really add much in terms of verification
- Abstraction of pipelining is something that could be achievable with ROHD, but is not (yet) implemented in base ROHD.

Read more about TL-Verilog here: <https://www.redwoodeda.com/tl-verilog>

### PyMTL

PyMTL is another attempt at creating an HDL in Python.  It is developed at Cornell University and the third version (PyMTL 3) is currently in Beta.  PyMTL aims to resolve a lot of the same things as ROHD, but with Python.  It supports conversion to SystemVerilog and simulation.

- The Python language trade-offs described in the above section on MyHDL apply to PyMTL as well.

Read more about PyMTL here: <https://github.com/pymtl/pymtl3> or <https://pymtl3.readthedocs.io/en/latest/>

### cocotb

cocotb is a Python-based testbench framework for testing SystemVerilog and VHDL designs.  It makes no attempt to represent hardware or create a simulator, but rather connects to other hardware simulators via things like VPI calls.

The cosimulation capabilities of cocotb are gratefully leveraged within the [ROHD Cosim](https://github.com/intel/rohd-cosim) package for cosimulation with SystemVerilog simulators.

Read more about cocotb here: <https://github.com/cocotb/cocotb> or <https://docs.cocotb.org/en/stable/>

----------------
2021 August 6
Author: Max Korbel <<max.korbel@intel.com>>

Copyright (C) 2021-2022 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause

---
title: "ROHD Example"
permalink: /docs/sample-example/
excerpt: "Sample example of using ROHD."
last_modified_at: 2024-01-04
toc: true
---

Please make sure you had setup your ROHD Framework before running the test. Information of installation can be found at [setup page]({{ site.baseurl }}{% link _get-started/02-installation.md %}).

## A full example of a counter module

To get a quick feel for what ROHD looks like, below is an example of what a simple counter module looks like in ROHD. Note that this is not the shortest way to describe a simple counter, but expanded to give some examples of different capabilities and be more easily comparable to designs in other languages like SystemVerilog.

```dart
// Import the ROHD package
import 'package:rohd/rohd.dart';

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
    addOutput('val', width: width);

    // We can use the `flop` function to automate creation of a `Sequential`.
    val <= flop(clk, reset: reset, en: en, val + 1);
  }
}

```

You can find an executable version of this counter example in [example/example.dart](https://github.com/intel/rohd/blob/main/example/example.dart).

## A more complex example

The below example demonstrates some aspects of the power of ROHD where writing equivalent design code in SystemVerilog can be challenging or impossible. The example is a port from an example used by Chisel.

The ROHD module TreeOfTwoInputModules is a succinct representation a logarithmic-height tree of arbitrary two-input/one-output modules.

```dart
class TreeOfTwoInputModules extends Module {
  
  final Logic Function(Logic a, Logic b) _op;
  final List<Logic> _seq = [];
  Logic get out => output('out');

  TreeOfTwoInputModules(List<Logic> seq, this._op) 
      : super(name: 'tree_of_two_input_modules') {
    if(seq.isEmpty) 
        throw Exception("Don't use TreeOfTwoInputModules with an empty sequence");
    
    for(var i = 0; i < seq.length; i++) {
      _seq.add(addInput('seq$i', seq[i], width: seq[i].width));
    }
    addOutput('out', width: seq[0].width);

    if(_seq.length == 1) {
      out <= _seq[0];
    } else {
      var a = TreeOfTwoInputModules(
        _seq.getRange(0, _seq.length~/2).toList(), _op
      ).out;
      var b = TreeOfTwoInputModules(
        _seq.getRange(_seq.length~/2, _seq.length).toList(), _op
      ).out;
      out <= _op(a, b);
    }
  }
}
```

Some interesting things to note:

- The constructor for `TreeOfTwoInputModules` accepts two arguments:

  - `seq` is a Dart `List` of arbitrary length of input elements.  The module dynamically assigns the input and output widths of the module to match the width of the input elements.  Additionally, the total number of inputs to the module is dynamically determined at run time.
  - `_op` is a Dart `Function` (in Dart, `Function`s are first-class and can be stored in variables).  It expects a function which takes two `Logic` inputs and provides one `Logic` output.

- This module recursively instantiates itself, but with different numbers of inputs each time.  The same module implementation can have a variable number of inputs and different logic without any explicit parameterization.

You could instantiate this module with some code such as:

```dart
var tree = TreeOfTwoInputModules(
  List<Logic>.generate(16, (index) => Logic(width: 8)),
  (Logic a, Logic b) => Mux(a > b, a, b).y
);
```

This instantiation code generates a list of sixteen 8-bit logic signals.  The operation to be performed (`_op`) is to create a `Mux` which returns `a` if `a` is greater than `b`, otherwise `b`.  Therefore, this instantiation creates a logarithmic-height tree of modules which outputs the largest 8-bit value.  Note that `Mux` also needs no parameters, as it can automatically determine the appropriate size of `y` based on the inputs.

A SystemVerilog implementation of this requires numerous module definitions and substantially more code.  Below is an output of the ROHD-generated SystemVerilog:

```verilog
module TreeOfTwoInputModules_3(
input logic [7:0] seq0,
input logic [7:0] seq1,
input logic [7:0] seq2,
input logic [7:0] seq3,
input logic [7:0] seq4,
input logic [7:0] seq5,
input logic [7:0] seq6,
input logic [7:0] seq7,
input logic [7:0] seq8,
input logic [7:0] seq9,
input logic [7:0] seq10,
input logic [7:0] seq11,
input logic [7:0] seq12,
input logic [7:0] seq13,
input logic [7:0] seq14,
input logic [7:0] seq15,
output logic [7:0] out
);
logic [7:0] out_1;
logic [7:0] out_0;

assign out = (out_1 > out_0) ? out_1 : out_0;  // mux
TreeOfTwoInputModules_2  tree_of_two_input_modules(
  .seq0(seq0),.seq1(seq1),.seq2(seq2),.seq3(seq3),
  .seq4(seq4),.seq5(seq5),.seq6(seq6),.seq7(seq7),.out(out_1)
);
TreeOfTwoInputModules_2  tree_of_two_input_modules_0(
  .seq0(seq8),.seq1(seq9),.seq2(seq10),.seq3(seq11),
  .seq4(seq12),.seq5(seq13),.seq6(seq14),.seq7(seq15),.out(out_0)
);
endmodule : TreeOfTwoInputModules_3

////////////////////

module TreeOfTwoInputModules_2(
input logic [7:0] seq0,
input logic [7:0] seq1,
input logic [7:0] seq2,
input logic [7:0] seq3,
input logic [7:0] seq4,
input logic [7:0] seq5,
input logic [7:0] seq6,
input logic [7:0] seq7,
output logic [7:0] out
);
logic [7:0] out_1;
logic [7:0] out_0;

assign out = (out_1 > out_0) ? out_1 : out_0;  // mux
TreeOfTwoInputModules_1  tree_of_two_input_modules(
  .seq0(seq0),.seq1(seq1),.seq2(seq2),.seq3(seq3),.out(out_1)
);
TreeOfTwoInputModules_1  tree_of_two_input_modules_0(
  .seq0(seq4),.seq1(seq5),.seq2(seq6),.seq3(seq7),.out(out_0)
);
endmodule : TreeOfTwoInputModules_2

////////////////////

module TreeOfTwoInputModules_1(
input logic [7:0] seq0,
input logic [7:0] seq1,
input logic [7:0] seq2,
input logic [7:0] seq3,
output logic [7:0] out
);
logic [7:0] out_1;
logic [7:0] out_0;

assign out = (out_1 > out_0) ? out_1 : out_0;  // mux
TreeOfTwoInputModules_0  tree_of_two_input_modules(
  .seq0(seq0),.seq1(seq1),.out(out_1)
);
TreeOfTwoInputModules_0  tree_of_two_input_modules_0(
  .seq0(seq2),.seq1(seq3),.out(out_0)
);
endmodule : TreeOfTwoInputModules_1

////////////////////

module TreeOfTwoInputModules_0(
input logic [7:0] seq0,
input logic [7:0] seq1,
output logic [7:0] out
);
logic [7:0] out_1;
logic [7:0] out_0;

assign out = (out_1 > out_0) ? out_1 : out_0;  // mux
TreeOfTwoInputModules  tree_of_two_input_modules(.seq0(seq0),.out(out_1));
TreeOfTwoInputModules  tree_of_two_input_modules_0(.seq0(seq1),.out(out_0));
endmodule : TreeOfTwoInputModules_0

////////////////////

module TreeOfTwoInputModules(
input logic [7:0] seq0,
output logic [7:0] out
);

assign out = seq0;

endmodule : TreeOfTwoInputModules
```

You can find an executable version of the tree example in [example/tree.dart](https://github.com/intel/rohd/blob/main/example/tree.dart).

## Content

* [Rapid Open Hardware Development (ROHD)?](./00-Introduction_to_ROHD.md#rapid-open-hardware-development-rohd)
* [Challenges in Hardware Industry](./00-Introduction_to_ROHD.md#challenges-in-hardware-industry)
* [Benefits of Dart for hardware development](./00-Introduction_to_ROHD.md#benefits-of-Dart-for-hardware-development)
* [Example of ROHD with Dart](./00-Introduction_to_ROHD.md#example-of-rohd-with-dart)

# Rapid Open Hardware Development (ROHD)

The Rapid Open Hardware Development Framework (ROHD) is a generator framework for describing and verifying hardware using the Dart programming language. It allows for the construction and traversal of a connectivity graph between module objects using unrestricted software. ROHD is not a new language, it is not a hardware description language (HDL), and it is not a version of High-Level Synthesis (HLS).

ROHD is a bold project with the goal of becoming the industry-standard choice for front-end hardware development, replacing SystemVerilog. It aims to address hardware problems in a similar way to Chisel, using Dart as its programming language of choice instead of Scala.

Feature of ROHD include:

* Full power of the modern **Dart language** for hardware design and verification.
* Easy **IP integration** and **interfaces**; using an IP is as easy as an import. Reduces tedious, redundant, and error prone aspects of integration.
* Develop **layers of abstraction** within a hardware design, making it more flexible and powerful.
* Conversion of modules to equivalent, human-readable, structurally similar **SystemVerilog** for integration or downstream tool consumption.
* **Simple and fast build**, free of complex build systems and EDA vendor tools.
* Use **modern IDEs** like Visual Studio Code, with excellent static analysis, fast autocomplete, built-in debugger, linting, git integration, extensions, and much more.
* Built-in event-based **fast simulator** with 4-value (0, 1, X, and Z) support and a **waveform dumper** to .vcd file format

## Challenges in Hardware Industry

Many people are curious as to why it is necessary to overhaul legacy systems that have proven effective for so long. Below, are some of the reasons why ROHD can be viewed as a powerful potential standard replacement.

1. **Limitations of SystemVerilog**: SystemVerilog (SV) is widely used in front-end hardware design and development, but it has limitations in hardware description. Many designers resort to using additional tools for hardware generation and connectivity due to these limitations.

2. **Inefficiency for Testbench Development**: Testbenches are software, and writing software in SystemVerilog is not ideal due to its inefficiency for software development. SystemVerilog's popularity can be attributed to the fact that it is convenient for verification engineers as it allows them to interact with hardware and related tools using the same language and tool stack.

3. **Difficulties in Integrating and Reusing Code**: Integrating and reusing SystemVerilog code can be extremely challenging and time-consuming.  Sometimes even just re-integrating a newer version of an existing component can take weeks.

4. **Slow Development Iteration**: Hardware development today is plagued by slow iteration time (usually build + simulation time), meaning that every time code is changed it takes a long time to determine if the change is effective. Smaller IPs may take only a few minutes or hours per iteration, but large SoCs can take days.

5. **Insufficient Alternative Solutions**: While there are alternative solutions such as Chisel and cocotb, they do not address all of the problems in hardware development. Some treat verification as a secondary consideration, despite the fact that verification often requires twice as much effort as design. Some solutions are academic in nature, but not suitable for production use. ROHD was developed as a solution that is ready for execution and addresses a wide range of front-end development needs.

6. **Lack of Open-Source Hardware Community**: The open-source hardware community is lacking. There are a few open-source generators or cores available, but their quality can be inconsistent. Finding open-source verification components is also a challenge, and there are no open-source or free tool stacks that can run UVM testbenches. This leaves many hardware engineers unfamiliar with open-source development.

7. **Need for Collaboration in the Hardware Industry**: The software industry has long recognized the benefits of collaborating on open-source projects, even with competitors. Hardware engineers, on the other hand, often spend too much time on struggling with poor tools and infrastructure. Instead of focusing on their competitive advantages, they are bogged down by these issues. Investing in open-source projects can help alleviate these challenges and improve the overall efficiency of hardware development.

## Benefits of Dart for Hardware Development

1. **Scalability**: The Dart programming language provides better scalability compared to SystemVerilog. It makes it easier to maintain and scale hardware designs as they become larger and more complex.

2. **Improved Productivity**: The Dart language is easier to use and learn and has better readability compared to SystemVerilog. This makes hardware development faster, easier, and more efficient.

3. **Enhanced Verification**: The use of Dart as a programming language for hardware design allows for better and more efficient verification of hardware designs. This helps to reduce design and verification time and improve the overall quality of the hardware.

4. **Multi-platform Support**: Dart was designed from the ground up to be multi-platform, meaning it can be used to develop hardware for a variety of platforms, including both software and hardware.

5. **Better Debugging**: Dart has better debugging and profiling tools compared to SystemVerilog, making it easier to identify and fix issues in hardware designs.

6. **Increased Reusability**: Dart with ROHD allows for the creation of reusable and modular hardware designs, making it easier to reuse components across multiple projects and speeding up the development process.

7. **Open-source Community**: The Dart language has a strong open-source community, providing a wealth of resources and support to hardware developers. This helps to drive innovation and development in the field.

## Example of ROHD with Dart

The below subsections offer some examples of implementations and syntax in ROHD. ROHD provides easy to read syntax and also high-level abstraction such as FSM, interface and pipeline.

No worries, we will cover all of this in the later chapter.

### A full example of a counter module

As of now, to get a quick feel for what ROHD looks like, below is an example of what a simple counter module looks like in ROHD.

```Dart
// Import the ROHD package
import 'package:rohd/rohd.Dart';

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

----------------
2023 February 13
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

Copyright (C) 2021-2023 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause

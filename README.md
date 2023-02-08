![ROHD Logo](doc/website/assets/images/rohd_logo.svg)

Rapid Open Hardware Development (ROHD) Framework
================================================

[![API Docs](https://img.shields.io/badge/API%20Docs-generated-success)](https://intel.github.io/rohd/api)
[![API Docs](https://img.shields.io/website?down_message=offline&up_color=blue&up_message=online&url=https%3A%2F%2Fintel.github.io%2Frohd%2F)](https://intel.github.io/rohd/)
[![Pub Version](https://img.shields.io/pub/v/rohd)](https://pub.dev/packages/rohd/versions)
[![Popularity](https://img.shields.io/pub/popularity/rohd)](https://pub.dev/packages/rohd/score)
[![Tests](https://github.com/intel/rohd/actions/workflows/general.yml/badge.svg?event=push)](https://github.com/intel/rohd/actions/workflows/general.yml)
[![Chat](https://img.shields.io/discord/1001179329411166267?label=Chat)](https://discord.gg/jubxF84yGw)
[![License](https://img.shields.io/badge/License-BSD--3-blue)](https://github.com/intel/rohd/blob/main/LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](https://github.com/intel/rohd/blob/main/CODE_OF_CONDUCT.md)

ROHD (pronounced like "road") is a framework for describing and verifying hardware in the Dart programming language.  ROHD enables you to build and traverse a graph of connectivity between module objects using unrestricted software.

The official website for ROHD can be found at https://intel.github.io/rohd, where you can access API documentation, tutorials, and other relevant information. Additionally, you can launch the repository on GitHub Codespace by clicking the button provided below.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=409325108)


## Describing Hardware in Dart with ROHD

Features of ROHD include:
- Full power of the modern **Dart language** for hardware design and verification
- Makes **validation collateral** simpler to develop and debug.  The [ROHD Verification Framework](https://github.com/intel/rohd-vf) helps build well-structured testbenches.
- Develop **layers of abstraction** within a hardware design, making it more flexible and powerful
- Easy **IP integration** and **interfaces**; using an IP is as easy as an import.  Reduces tedious, redundant, and error prone aspects of integration
- **Simple and fast build**, free of complex build systems and EDA vendor tools
- Built-in event-based **fast simulator** with **4-value** (0, 1, X, and Z) support and a **waveform dumper** to .vcd file format
- Conversion of modules to equivalent, human-readable, structurally similar **SystemVerilog** for integration or downstream tool consumption
- **Run-time dynamic** module port definitions (numbers, names, widths, etc.) and internal module logic, including recursive module contents
- Simple, free, **open source tool stack** without any headaches from library dependencies, file ordering, elaboration/analysis options, +defines, etc.
- Excellent, simple, fast **unit-testing** framework
- **Less verbose** than alternatives (fewer lines of code)
- Enables **higher quality** development
- Fewer bugs and lines of code means **shorter development schedule**
- Support for **cosimulation with verilog modules** and **instantiation of verilog modules** in generated SystemVerilog code
- Use **modern IDEs** like Visual Studio Code, with excellent static analysis, fast autocomplete, built-in debugger, linting, git integration, extensions, and much more
- Simulate with **various abstraction levels of models** from architectural, to functional, to cycle-accurate, to RTL levels in the same language and environment.

ROHD is *not* a new language, it is *not* a hardware description language (HDL), and it is *not* a version of High-Level Synthesis (HLS).  ROHD can be classified as a generator framework.

You can think of this project as an attempt to *replace* SystemVerilog and related build systems as the front-end methodology of choice in the industry.

One of ROHD's goals is to help grow an open-source community around reusable hardware designs and verification components.

### The Challenge of Justifying Trying a New Language

<a href="https://stackoverflow.com/questions/53007782/what-benefits-does-chisel-offer-over-classic-hardware-description-languages">This StackOverflow answer</a> about why it's worth trying Chisel (an alternative to ROHD) contains valuable insight into why it is difficult in general to justify a new language to someone who hasn't used it before:

> Language *power* is notoriously difficult to objectively evaluate. Paul Graham describes this as the "Blub Paradox" in his <a href="http://www.paulgraham.com/avg.html">"Beating the Averages" essay</a>. Graham's thesis is that an engineer proficient in a less powerful language cannot evaluate the utility of a more powerful language.

If you're thinking "SystemVerilog is just fine, I don't need something new", it is worth reading either or both of the StackOverflow answer and the Paul Graham essay.

## Development Recommendations
- The [ROHD Verification Framework](https://github.com/intel/rohd-vf) is a UVM-like framework for building testbenches for hardware modelled in ROHD.
- Visual Studio Code (vscode) is a great, free IDE with excellent support for Dart.  It works well on all platforms, including native Windows or Windows Subsystem for Linux (WSL) which allows you to run a native Linux kernel (e.g. Ubuntu) within Windows.  You can also use vscode to develop on a remote machine with the Remote SSH extension.
    - vscode: https://code.visualstudio.com/
    - WSL: https://docs.microsoft.com/en-us/windows/wsl/install-win10
    - Remote SSH: https://code.visualstudio.com/blogs/2019/07/25/remote-ssh
    - Dart extension for vscode: https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code

## Installation & Setup

Please check on the [ROHD setup page](https://intel.github.io/rohd/get-started/setup/) for the [pub](https://pub.dev/) packages.

To install the latest release, a command as simple as 

```cmd
$ dart pub add rohd
```

or 

add a line like this to your package's pubspec.yaml (and run `dart pub get`)

```yaml
dependencies:
  rohd: ^0.4.1
```

### Importing

Then, you can start by importing ROHD.

```dart
import 'package:rohd/rohd.dart'; 
```

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


## Contributing

ROHD is under active development.  If you're interested in contributing, have feedback or a question, or found a bug, please see [CONTRIBUTING.md](https://github.com/intel/rohd/blob/main/CONTRIBUTING.md).

## License

[SPDX-License-Identifier: BSD-3-Clause](https://github.com/intel/rohd/blob/main/LICENSE)

----------------
2021 August 6  
Author: Max Korbel <<max.korbel@intel.com>>

 
Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause

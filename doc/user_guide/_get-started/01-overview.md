---
title: "Overview"
permalink: /get-started/overview/
excerpt: "Overview of ROHD framework."
last_modified_at: 2024-01-04
toc: true
---

## Describing Hardware in Dart with ROHD

ROHD (pronounced like "road") is a framework for describing and verifying hardware in the Dart programming language.

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
- Leverage the [ROHD Hardware Component Library (ROHD-HCL)](https://github.com/intel/rohd-hcl) with reusable and configurable design and verification components.
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

Because it is designed with asynchronous requests in mind (i.e. sending a request to a server and not freezing the application while it waits for a response), Dart has `async`/`await` and `Future`s built in, with [concurrent programming](https://dart.dev/language/concurrency).  These constructs enable code to execute in parallel without multithreading.  These chacteristics make modelling hardware very easy.

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

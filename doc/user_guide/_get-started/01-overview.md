---
title: "Overview"
permalink: /get-started/overview/
excerpt: "Overview of ROHD framework."
last_modified_at: 2024-01-04
toc: true
---

## Describing Hardware in Dart with ROHD

ROHD (pronounced like "road") is a silicon-proven framework for describing and verifying hardware in the Dart programming language.

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

[Dart](https://dart.dev/) is a modern, relatively new, [extremely popular](https://survey.stackoverflow.co/2024/technology#most-popular-technologies) ([top-20](https://redmonk.com/sogrady/2024/09/12/language-rankings-6-24/)) language developed by Google.  It is designed with client-side application development in mind (e.g. apps and websites), but also has great performance for general tasks.  It adopts some of the most loved syntax and features from languages like C++, Java, C#, JavaScript/TypeScript, and Kotlin.  Dart is extremely user-friendly, fun to use, and [**easy to learn** with **excellent documentation**](https://dart.dev/language).  The excellent, fast static analysis with a modern IDE with autocomplete makes it easy to learn as you work.  Dart has a lot of great modern language features, including null safety.

Because it is designed with asynchronous requests in mind (i.e. sending a request to a server and not freezing the application while it waits for a response), Dart has `async`/`await` and `Future`s built in, with [concurrent programming](https://dart.dev/language/concurrency).  These constructs enable code to execute in parallel without multithreading.  These characteristics make modelling, interacting with, and verifying hardware very easy.

Dart can compile to native machine code, but also includes its own high-performance VM and a JIT compiler.  During development, you can use a feature called "hot reload" to change code while the program is actively executing.

Dart has an excellent package manager called "pub" (<https://pub.dev>).  It is possible to host a private Dart Pub server for packages that shouldn't be shared broadly (e.g. Top-Secret IP).

### The Challenge of Justifying Trying a New Language

[This StackOverflow answer](https://stackoverflow.com/questions/53007782/what-benefits-does-chisel-offer-over-classic-hardware-description-languages) about why it's worth trying Chisel (an alternative to ROHD) contains valuable insight into why it is difficult in general to justify a new language to someone who hasn't used it before:

> Language *power* is notoriously difficult to objectively evaluate. Paul Graham describes this as the "Blub Paradox" in his ["Beating the Averages" essay](http://www.paulgraham.com/avg.html). Graham's thesis is that an engineer proficient in a less powerful language cannot evaluate the utility of a more powerful language.

If you're thinking "SystemVerilog is just fine, I don't need something new", it is worth reading either or both of the StackOverflow answer and the Paul Graham essay.

### More Information on Dart

Try out Dart instantly from your browser here (it supports ROHD too!): <https://dartpad.dev/?null_safety=true>

See some Dart language samples here: <https://dart.dev/language>

For more information on Dart and tutorials, see <https://dart.dev/> and <https://dart.dev/overview>

## Trusting ROHD

A common initial concern when adopting ROHD is the matter of trust.  How can one trust that there is equivalence between what was developed and simulated in ROHD and what gets generated in the output SystemVerilog?

### Unoptimized, simple, one-to-one mapping

ROHD generates outputs one-to-one with the objects constructed in the original Dart.  There is no magic compiler under the hood that's transforming or optimizing your design.  A module instantiated in a ROHD model will directly map to a piece of equivalent generated SystemVerilog.  This is key to generating logically equivalent, structurally similar outputs with instance and signal names and hierarchy maintained.  This means there are two somewhat independent pieces of ROHD generation:

1. How to generate an output based on an instance in the ROHD model.
2. How to compose and connect instances together in the generated output.

These two steps are a thin layer between the original design intent and the generated output.  More complex abstractions are created by composing together lower-level building blocks.  One can always trace exactly how an output was created.

### Extensive unit testing across simulators

Generation and composition are extensively tested in the ROHD test suite. Every feature, argument, and composition mechanism is unit-tested before it can be merged in.  Most of these tests are written using test vectors which are then run on both the ROHD simulator and in a SystemVerilog simulator on the generated outputs, ensuring identical behavior between the two simulators.

Generally speaking, the ROHD simulations are *stricter* and *more predictable* than SystemVerilog simulators can be. For example, in SystemVerilog, transitions between invalid signal states (`x` and `z`) can trigger as edges in sequential logic, whereas in ROHD they cannot, and in fact would propagate an `x` instead.  In SystemVerilog, if you violate a `unique` on a `case`, you get a *warning printed in the logs*, whereas in ROHD you get an `x` out of that block.

ROHD is also both more flexible in design intent and more restrictive in SystemVerilog generation.  It is easy in SystemVerilog to describe non-synthesizable logic, but ROHD makes it very difficult to generate SystemVerilog which would imply an ambiguous design.  ROHD also helps ensure lint-clean SystemVerilog generation, even if that means it would become more verbose. Since ROHD does not generate everything that SystemVerilog *could* do, it means the surface area to test is dramatically reduced for equivalence of simulator behavior.

### Trusting EDA tools in general

How does anyone trust any EDA tool in general?  Usually a combination of

- testing methodologies to ensure the tool works (and doesn't break with new versions),
- a history of real-world usage, and
- sanity checking the results.

Bugs are still found regularly in "industry-standard" EDA tools, including between simulators and synthesis tools from the same developer and in formal analysis tools. Even if you run formal tools (equivalence, verification, etc.) on a design, those tools themselves were not formally proven. There's a lot of human-written software between the source code you wrote and the design you tape out. It's not a bad thing to do some sanity checking on critical designs for *any* EDA tool (e.g. reviewing outputs manually, paranoia checks, running other tools to compare results, formal analysis, etc.).

ROHD's thin generation layer, real-world usage, and open-source, well-tested implementation should inspire a good amount of confidence. In the end, it's up to you, the user, to decide how much you trust the tools you're using and what additional steps are worth taking to mitigate risk.

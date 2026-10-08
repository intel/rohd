---
title: "Overview"
permalink: /get-started/overview/
excerpt: "Overview of ROHD framework."
last_modified_at: 2026-07-16
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

A reasonable concern when adopting any hardware generator is whether the model that was developed and simulated matches the generated RTL. ROHD addresses that concern by keeping generation inspectable, testing the same behavior through independent simulation paths, and making the complete implementation available for review.

### Inspectable, structural generation

ROHD is an RTL construction framework, not an HLS compiler that infers a microarchitecture from an algorithm. Modules, signals, assignments, and conditional or sequential logic in a ROHD model are translated into recognizable SystemVerilog structures. Module hierarchy and user-provided names are preserved where the generated structure permits it.

Generation is not a literal one-object-to-one-declaration mapping. ROHD performs mechanical simplifications such as collapsing intermediate connections and pruning unused objects. These transformations reduce unnecessary generated code without choosing an architecture on the designer's behalf. The result is intended to remain human-readable and structurally close enough to the model that a reviewer can trace signals and module boundaries through the generated RTL.

Generated SystemVerilog is also an ordinary artifact: it can be inspected, diffed, linted, simulated, synthesized, or checked with formal tools before it is accepted into a downstream flow.

### Safer SystemVerilog by construction

ROHD does not expose arbitrary SystemVerilog syntax for synthesizable hardware construction. Its APIs describe hardware intent, and the generator selects the appropriate SystemVerilog construct. This makes entire classes of legal-looking but incorrect RTL difficult or impossible to express.

For example, a conditional assignment is written the same way inside ROHD `Combinational` and `Sequential` blocks. The generator emits blocking assignments (`=`) in the corresponding `always_comb` block and non-blocking assignments (`<=`) in the corresponding `always_ff` block. A developer cannot accidentally select the wrong assignment semantics because that choice is not exposed by the ROHD API.

ROHD also checks widths and block configurations and detects problematic patterns such as combinational write-after-read that could produce simulation and synthesis mismatches. These restrictions do not guarantee that every constructible design is correct, but they substantially reduce the SystemVerilog surface area where subtle mistakes can hide.

Producing lint-clean SystemVerilog is also an explicit design goal. ROHD prefers explicit, sometimes more verbose output when it avoids common lint or portability issues, sanitizes and uniquifies generated names, manages widths, and removes unnecessary intermediate signals and assignments. The cross-simulator test infrastructure treats unexpected Icarus Verilog warnings as failures by default, and targeted tests protect against known lint-sensitive generation patterns. No generator can guarantee zero diagnostics under every vendor and ruleset, but ROHD actively designs and tests its output to minimize them.

### The same tests through independent simulators

The ROHD test suite repeatedly checks the boundary between the in-memory model and generated SystemVerilog. Its [`SimCompare`](https://github.com/intel/rohd/blob/main/lib/src/utilities/simcompare.dart) utility applies test vectors to the built-in ROHD simulator, converts those vectors into a SystemVerilog testbench, and runs the generated design with Icarus Verilog. The [tests](https://github.com/intel/rohd/tree/main/test) use this pattern across arithmetic, conditional and sequential logic, arrays, interfaces, nets, naming, and module composition.

The [continuous integration workflow](https://github.com/intel/rohd/blob/main/.github/workflows/general.yml) installs Icarus Verilog and runs the project tests for every pull request and every push to the main branch. A change to simulation or generation therefore has to satisfy both execution paths before it can be merged.

### Deliberately conservative simulation semantics

ROHD supports four-state values (`0`, `1`, `x`, and `z`), but it does not attempt to reproduce every permissive or tool-specific corner of SystemVerilog simulation. Ambiguous behavior is generally rejected or propagated as unknown instead of being accepted silently. For example, transitions involving `x` or `z` are not treated as valid clock edges, and conditional logic propagates unknown values when selecting a deterministic branch would hide ambiguity.

This conservative behavior helps expose questionable assumptions earlier. It also means that designs which intentionally depend on simulator-specific `x` or `z` behavior deserve explicit comparison in the downstream SystemVerilog simulator.

### Trusting ROHD like any other EDA tool

Trust in an EDA tool is not all-or-nothing. Engineers decide how much confidence to place in simulators, synthesizers, linters, and formal tools based on their testing, track record, transparency, and the consequences of a failure. Familiarity and vendor reputation can make established SystemVerilog tools feel unquestionably reliable, but those tools also contain bugs, can disagree with one another, and are part of the same chain of human-written software.

ROHD belongs in that same evaluation. Its structural output, independent simulation paths, automated regression testing, open-source implementation, and use in real silicon are evidence that can inform a team's confidence. They are not a claim that ROHD is infallible or more trustworthy than every alternative, just as the history of an established EDA tool is not proof that it is infallible.

The appropriate level of additional checking depends on the project and the cost of being wrong, not simply on whether the tool is ROHD or a familiar SystemVerilog tool. A team may rely on normal regression testing for one design and add independent simulation, output review, or formal analysis for another. That proportional judgment is a normal part of using any EDA tool.

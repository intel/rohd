---
title: "Comparison with Alternatives"
permalink: /docs/comparison-with-alternatives/
excerpt: "Comparison with Alternatives"
last_modified_at: 2024-01-04
toc: true
---

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

- TL-Verilog makes RTL design easier, especially when pipelining, but doesn't really add much in terms of verification
- ROHD also supports a [pipelining abstraction](https://intel.github.io/rohd-website/docs/pipelines/).

Read more about TL-Verilog here: <https://www.redwoodeda.com/tl-verilog>

### PyMTL

PyMTL is another attempt at creating an HDL in Python.  It is developed at Cornell University and the third version (PyMTL 3) is currently in Beta.  PyMTL aims to resolve a lot of the same things as ROHD, but with Python.  It supports conversion to SystemVerilog and simulation.

- The Python language trade-offs described in the above section on MyHDL apply to PyMTL as well.

Read more about PyMTL here: <https://github.com/pymtl/pymtl3> or <https://pymtl3.readthedocs.io/en/latest/>

### cocotb

cocotb is a Python-based testbench framework for testing SystemVerilog and VHDL designs.  It makes no attempt to represent hardware or create a simulator, but rather connects to other hardware simulators via things like VPI calls.

The cosimulation capabilities of cocotb are gratefully leveraged within the [ROHD Cosim](https://github.com/intel/rohd-cosim) package for cosimulation with SystemVerilog simulators.

Read more about cocotb here: <https://github.com/cocotb/cocotb> or <https://docs.cocotb.org/en/stable/>

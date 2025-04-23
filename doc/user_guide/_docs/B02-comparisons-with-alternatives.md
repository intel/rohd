---
title: "Comparison with Alternatives"
permalink: /docs/comparison-with-alternatives/
excerpt: "Comparison with Alternatives"
last_modified_at: 2025-03-19
toc: true
---

There are a lot of options for developing hardware.  This section briefly discusses some popular alternatives to ROHD and some of their strengths and weaknesses.

There is a conceptual difference between a *compiled hardware language* and an *embedded generator framework*.  ROHD falls in the latter category because it is embedded into a software language (Dart) and is fundamentally a package or library for modelling hardware, simulating it, and generating outputs (e.g. SystemVerilog).  By contrast, compiled hardware languages (e.g. VHDL, SystemVerilog) are independent langauges, and a compiler stack reads the code and converts it into some synthesizable/simulatable representation. There are benefits and downsides to each approach, and some solutions are a mixture between these.

- **Language expressiveness:** A compiled hardware language can add specific syntax that can make it easier and more natural to describe hardware, whereas an embedded framework would need to remain within the bounds of the programming language. However, compiled hardware languages can become limiting in their expressiveness, requiring additional language features to expand capabilities.  Meanwhile, an embedded framework has the full software language available to control hardware construction.
- **Source alignment:** In a compiled language, it is reasonable to expect that the *names of variables* would have an impact on *generated outputs*.  For example, if you name a `logic abc` for a register in SystemVerilog, you might reasonably expect a compiled netlist to still have that name `abc` somewhere in it.  In a generator framework (with no [reflection](https://en.wikipedia.org/wiki/Reflective_programming)), you'd need to explicitly name a signal with a `String` for the name to show up in a generated output. The trade-off here is succinctness vs. flexibility.  You can potentially write less repetitive code for simple descriptions in a compiled language, but you have greater flexibility and control in the generator framework for more configurable and complex designs.
- **Optimization and predictability:** A compiler can spend time optimizing/lowering a design which could potentially give you better outcomes in synthesis, simulation, etc. However, the more optimization there is, the harder it is to map results back to the original source code or predict how a change in the source will affect the output.  For at least the near future, many engineers are still concerned with inspecting the generated outputs, so readability is important.  More importantly, in ASIC development just before tape-out, there may be tiny bug fixes needed to the design that are done by hand rather than with full re-synthesis.  If a small change in the source code can have a large or unpredictable set of changes in the final hardware, then these small manual edits become impossible.  Additionally, a lot of the optimization for simulation and synthesis in standard EDA tools, once it's in SystemVerilog, is optimized for non-bit-blasted representations.  Most compiler stacks are not producing good enough optimizations to outperform what those standard EDA tools already do, so the optimizations may not be adding a lot of value.
- **Algorithm Abstraction**: Some compiled languages (e.g. High-Level Synthesis) actually compile some algorithmic intent and constraints into a performant implementation, for example with automatic pipelining.  In practice, this kind of approach requires re-validating the generated outputs since that's where the actual cycle-accurate hardware exists. Generator frameworks, by contrast, achieve abstraction via composition: automating the way you compose and construct pieces of hardware provides a layer of abstraction for building more complex designs. The generator framework approach grounds the designer in a hardware mindset instead of a more detached algorithmic one.
- **Determination of synthesizability:** Compiled languages usually still have a capability of doing some "generation" or parameterization that do not represent actual hardware operations (e.g. `generate` in SystemVerilog). They also might have pure-software constructs for verification purposes that are neither synthesizable nor generation-time compatible (e.g. SystemVerilog classes).  This can create a blurry barrier for developers where it's unclear which language constructs can be used to represent or control generation of hardware, and which ones are non-synthesizable.  A generator framework can eliminate such blurriness: hardware objects represent hardware, and software constructs used to generate those objects do not.
- **Automation Development:** In a compiled language, developing a new EDA tool often requires either/both parsing the language and/or generating the language. This is a substantial barrier for tool development. Even more concerning is that any new language advancement can only be leveraged once all required tools are able to handle it.  This is a serious problem that often forces engineers to leverage only the subset of language features which all tools support.  This also instills an aversion in developers to use new language features since things may work initially in one context, but then a tool incompatibility downstream may force a rewrite later.  By contrast, a generator language can *reduce* barriers to EDA development since the object model already exists and generation is already handled.
- **Ecosystem:** A development ecosystem with editors, static analysis tools, reusable packages, documentation, and community is extremely valuable. Building a thriving ecosystem is very difficult, and the relative size of the hardware development community compared to that of software development only makes this more challenging. Even industry standards like SystemVerilog and VHDL have a very limited ecosystem (compared to Python, Dart, etc.).  While compiled languages are on their own, embedded frameworks instantly gain the ecosystem of the underlying language, which is a huge advantage.

### SystemVerilog

SystemVerilog is the most popular HDL (hardware descriptive language).  It is based on Verilog, with additional software-like constructs added on top of it.  Some major drawbacks of SystemVerilog are:

- SystemVerilog is old, verbose, and limited, which makes code more bug-prone
- Integration of IPs at SOC level with SystemVerilog is very difficult and time-consuming.
- Validation collateral is hard to develop, debug, share, and reuse when it is written in SystemVerilog.
- Building requires building packages and libraries with proper `include ordering based on dependencies, ordering of files read by compilers in .f files, correctly specifiying order of package and library dependencies, and correct analysis and elaboration options.  This is an area that drains many engineers' time debugging.
- Build and simulation are dependent on expensive EDA vendor tools or incomplete open-source alternatives.  Every tool has its own intricacies, dependencies, licensing, switches, etc. and different tools may synthesize or simulate the same code in a functionally different way.
- Designing configurable and flexible modules in pure SystemVerilog usually requires parameterization, compile-time defines, and "generate" blocks, which can be challenging to use, difficult to debug, and restrictive on approaches.
  - Engineers often rely on perl or python scripts to bridge the gap for iteratively generating more complex hardware or stitching together large numbers of modules.
- Testbenches are, at the end of the day, software.  SystemVerilog is arguably a poor programming language, since it is primarily focused at hardware description, which makes developing testbenches excessively challenging.  Basic software quality-of-life features are missing in SystemVerilog.
  - Mitigating the problem by connecting to other languages through DPI calls (e.g. C++ or SystemC) has it's own complexities with extra header files, difficulty modelling parallel execution and edge events, passing callbacks, etc.
  - [UVM](https://en.wikipedia.org/wiki/Universal_Verification_Methodology) throws macros and boilerplate at the problem, which doesn't resolve the underlying limitations.

ROHD aims to enable all the best parts of SystemVerilog, while completely eliminating each of the above issues.  Build is automatic and part of Dart, packages and files can just be imported as needed, no vendor tools are required, hardware can be constructed using all available software constructs, and Dart is a fully-featured modern software language with modern features.

You can read more about SystemVerilog here: <https://en.wikipedia.org/wiki/SystemVerilog>.

VHDL is another of the most popular HDLs, with many similar characteristics to Verilog <https://en.wikipedia.org/wiki/VHDL>.

### Chisel

Chisel is a domain specific language (DSL) built on top of [Scala](https://www.scala-lang.org/), which is built on top of the Java virtual machine (JVM).  The goals of Chisel are somewhat aligned with the goals of ROHD.  Chisel can also convert to SystemVerilog.

- The syntax of Scala (and thus Chisel) is probably less familiar-feeling to most hardware engineers, and it can be more verbose than ROHD with Dart.
- Scala and the JVM are arguably less user-friendly to debug than Dart code.
- Chisel is focused mostly on the hardware *designer* rather than the *validator*.  Many of the design choices for the language are centered around making it easier to parameterize and synthesize logic.  ROHD was created with validators in mind.
- Chisel generates logic that's closer to a netlist than what a similar implementation in SystemVerilog would look like.  This can make it difficult to debug or validate generated code.  ROHD generates structurally similar SystemVerilog that looks close to how you might write it.
- Chisel does not have a native hardware simulator in the same way that ROHD does.  A variety of simulation approaches exist for Chisel.  Some operate on the intermediate representations between the source code into the compiler stack.  Most teams rely on other simulators (e.g. Verilator) to simulate the generated SystemVerilog, which leaves validation to the most of the same problems as verifying any other SystemVerilog design.
- Chisel has some amount of code reflection, meaning the structure of the generator code you write in Chisel (e.g. variable names) has an impact on the generated output.  Conversely, in ROHD, the Dart code written is completely independent of the model which the code generates.  This means that sometimes simpler designs can be a little more succinct in Chisel, but ROHD excels at scaling configurability.
- Parameterization and configuration of hardware in Chisel is often determined prior to module construction, similar to how SystemVerilog does it.  In ROHD, you can dynamically determine port widths, module contents, etc. based on introspecting the signals connected to it (or anything else).  This provides a lot more flexibility and reusability for hardware developed with ROHD.

Read more about Chisel here: <https://www.chisel-lang.org/>

### MyHDL (Python)

There have been a number of attempts to create a HDL on top of Python, but it appears the MyHDL is one of the most mature options.  MyHDL has many similar goals to ROHD, but chose to develop in Python instead of Dart.  MyHDL can also convert to SystemVerilog.

- MyHDL uses "generators" and decorators to help model concurrent behavior of hardware, which is arguably less user-friendly and intuitive than async/await and event based simulation in ROHD.
- While Python is a great programming langauge for the right purposes, some language features of Dart make it better for representing hardware.  Above is already mentioned Dart's asynchronous programming capabilities, which don't exist in the same way in Python.  Dart is statically typed with null safety while Python is dynamically typed, which can make static analysis (including IDE integration, type safety, etc.) more challenging in Python.  Python can also be challenging to scale to large programs without careful architecting.
- Python is generally slower to execute than Dart.
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
- The general approach is similar to Chisel, described above, but with Python.

Read more about PyMTL here: <https://github.com/pymtl/pymtl3> or <https://pymtl3.readthedocs.io/en/latest/>

### cocotb

cocotb is a Python-based testbench framework for testing SystemVerilog and VHDL designs.  It makes no attempt to represent hardware or create a simulator, but rather connects to other hardware simulators via things like VPI calls.

The cosimulation capabilities of cocotb are gratefully leveraged within the [ROHD Cosim](https://github.com/intel/rohd-cosim) package for cosimulation with SystemVerilog simulators.

Read more about cocotb here: <https://github.com/cocotb/cocotb> or <https://docs.cocotb.org/en/stable/>


### Spade

### PipelineC

### Sus

### DFiant HDL
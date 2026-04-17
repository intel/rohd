# Architecture

This document describes the organization and architecture of the ROHD framework. It is not necessary to fully understand all this detail in order to use ROHD, but it could be helpful for debug or contributing.

## Major Concepts

### Logic and LogicValue

The `Logic` is the fundamental "wire" that connects signals throughout a hardware design. It behaves very similarly to a `logic` in SystemVerilog. It has a fixed width determined at the time of construction. At any point in time, it has one value of type `LogicValue`. A `Logic` can be connected to up to one source, and any number of destinations. All connections must be the same width.

Any time the source of a `Logic` changes, it propagates the change outwards to its destinations. There are various events that can be subscribed to related to signal value transitions on `Logic`.

A `LogicValue` represents a multi-bit (including 0-bit and 1-bit) 4-value (`1`, `0`, `x`, `z`) static value. It is immutable.

### Module

The `Module` is the fundamental building block of hardware designs in ROHD. They have clearly defined inputs and outputs, and all logic contained within the module should connect either/both from inputs and to outputs. The ROHD framework will determine at `build()` time which logic sits within which `Module`. Any functional operation, whether a simple gate or a large module, is implemented as a `Module`.

Every `Module` defines its own functionality. This could be through composition of other `Module`s, or through custom functional definition. For a custom functionality to be convertible to an output (e.g. SystemVerilog), it has to explicitly define how to convert it (via `SystemVerilog` or `InlineSystemVerilog`). Any time the input of a custom functionality `Module` toggles, the outputs should correspondingly change, if necessary.

### Simulator

The `Simulator` acts as a statically accessible driver of the overall simulation. Anything can register arbitrary `Function`s to be executed at any timestamp that has not already occurred. The `Simulator` does not need to understand much about the functionality of a design; rather, the `Module`s and `Logic`s are responsible for propagating changes throughout.

### Synthesizer

A separate type of object responsible for taking a `Module` and converting it to some output. ROHD includes two built-in synthesizers:

- `SystemVerilogSynthesizer` — Converts a `Module` hierarchy into SystemVerilog files. Each `Module` with custom functionality must implement the `SystemVerilog` or `InlineSystemVerilog` mixin so the synthesizer knows how to emit it.
- `NetlistSynthesizer` — Converts a `Module` hierarchy into a JSON netlist following the [Yosys JSON format](https://yosyshq.readthedocs.io/projects/yosys/en/0.45/cmd/write_json.html). The output contains `modules` with `ports`, `cells`, and `netnames` sections, and is compatible with open-source EDA tools that consume `yosys write_json` output.

Both synthesizers are driven by `SynthBuilder`, which walks the module hierarchy bottom-up, deduplicates identical module definitions, and produces a set of `SynthesisResult` objects (either `SynthesisResult` for SystemVerilog or `NetlistSynthesisResult` for netlist JSON).

## Organization

All the code for the ROHD framework library is in `lib/src/`, with `lib/rohd.dart` exporting the main stuff for usage.

### Collections

Software collections that are useful for high-performance internal implementation details in ROHD.

### Exceptions

Exceptions that the ROHD framework may throw.

### Modules

Contains a collection of `Module` implementations that can be used as primitive building blocks for ROHD designs.

### Synthesizers

Contains logic for synthesizing `Module`s into some output. It is structured to maximize reusability across different output types. The `SystemVerilogSynthesizer` generates `.sv` files, while the `NetlistSynthesizer` generates Yosys-compatible JSON netlists. `SynthBuilder` orchestrates the synthesis process for both, handling hierarchy traversal and definition deduplication.

### Utilities

Various generic objects and classes that may be useful in different areas of ROHD.

### Values

Definitions for things related to `LogicValue`.

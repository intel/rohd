---
title: "Generating Outputs"
permalink: /docs/generation/
last_modified_at: 2023-11-13
toc: true
---

Hardware in ROHD is convertible to an output format via `Synthesizer`s, the most popular of which is SystemVerilog. Hardware in ROHD can be converted to logically equivalent, human-readable SystemVerilog with structure, hierarchy, ports, and names maintained.

The simplest way to generate SystemVerilog is with the helper method `generateSynth` in `Module`:

```dart
void main() async {
    final myModule = MyModule();
    
    // remember that `build` returns a `Future`, hence the `await` here
    await myModule.build();

    final generatedSv = myModule.generateSynth();

    // you can print it out...
    print(generatedSv);

    // or write it to a file
    File('myHardware.sv').writeAsStringSync(generatedSv);
}
```

The `generateSynth` function will return a `String` with the SystemVerilog `module` definitions for the top-level it is called on, as well as any sub-modules (recursively).  You can dump the entire contents to a file and use it anywhere you would any other SystemVerilog.

## Controlling naming

### Modules

Port names are always maintained exactly in generated SystemVerilog, so they must always be unique and sanitary (valid) SystemVerilog.

`Module`s have two names:

- The `definitionName`, which maps to the name of the module declaration in SystemVerilog.
  - If you want to ensure this does not change (e.g. uniquified because multiple different declarations have the same `definitionname`), set `reserveDefinitionName` to `true`.
- The `name`, which maps to the instance name when that instance is instantiated as a sub-module of another module.
  - If you want to ensure this does not change (e.g. uniquified because other signals or sub-modules would have the same name), then set `reserveName` to `true`.

### Internal signals

Internal signals, unlike ports, don't need to always have the same exact name as in the original hardware definition.

- If you do not name a signal, it will get a default name.  Generated code will attempt to avoid keeping that intermediate signal around (declared) if possible.
- If you do name a signal, by default it will be characterized as `renameable`.  This means it will try to keep that name in generated output, but may rename it for uniquification purposes.
- If you want to make sure an internal signal maintains exactly the name you want, you can mark it explicitly with `reserved`.
- You can downgrade a named signal as well to `mergeable` or even `unnamed`, if you care less about its name in generated outputs and prefer that others will take over.

### Unpreferred names

The `Naming.unpreferredName` function will modify a signal name to indicate to downstream flows that the name is preferably omitted from the output, but preferable to an unnamed signal. This is generally most useful for things like output ports of `InlineSystemVerilog` modules.

## More advanced generation

Under the hood of `generateSynth`, it's actually using a [`SynthBuilder`](https://intel.github.io/rohd/rohd/SynthBuilder-class.html) which accepts a `Module` and a `Synthesizer` (usually a `SystemVerilogSynthesizer`) as arguments. This `SynthBuilder` can provide a collection of `String` file contents via `getFileContents`, or you can ask for the full set of `synthesisResults`, which contains `SynthesisResult`s which can each be converted `toSynthFileContents` but also has context about the `module` it refers to, the `instanceTypeName`, etc. With these APIs, you can easily generate named files, add file headers, ignore generation of some modules, generate file lists for other tools, etc. The `SynthBuilder.multi` constructor makes it convenient to generate outputs for multiple independent hierarchies.

## Netlist Synthesis

In addition to SystemVerilog, ROHD can synthesize a design to a JSON netlist that follows the [Yosys JSON format](https://yosyshq.readthedocs.io/projects/yosys/en/0.45/cmd/write_json.html). This is the same format produced by `yosys write_json` and consumed by many open-source EDA tools and viewers.

### Basic usage

```dart
void main() async {
    final myModule = MyModule();
    await myModule.build();

    final netlistJson = await NetlistSynthesizer().synthesizeToJson(myModule);

    // write it to a file
    File('myDesign.rohd.json').writeAsStringSync(netlistJson);
}
```

### Output format

The produced JSON has the following top-level structure:

```json
{
  "creator": "ROHD ...",
  "modules": {
    "<definition_name>": {
      "attributes": { "top": 1, ... },
      "ports": {
        "<port_name>": { "direction": "input"|"output"|"inout", "bits": [...] }
      },
      "cells": {
        "<cell_name>": { "type": "...", "connections": { ... } }
      },
      "netnames": {
        "<signal_name>": { "bits": [...], "hide_name": 0|1 }
      }
    }
  }
}
```

Key sections per module:

- **`ports`** — The module's input, output, and inout ports. Each port has a `direction` and a `bits` array of integer wire IDs.
- **`cells`** — Sub-module instances and primitive gate cells (e.g. `$and`, `$mux`, `$dff`, `$add`). Each cell has a `type`, and in full mode, `connections` mapping port names to wire ID vectors.
- **`netnames`** — Named signals (wires) internal to the module. Each entry maps a signal name to its `bits` vector.

The top-level module is marked with `"top": 1` in its `attributes`.

### Slim mode

Passing `NetlistOptions(slimMode: true)` produces a compact JSON that omits cell `connections`. This is useful for transmitting the design dictionary (module hierarchy, ports, signals) without the full connectivity — a remote agent can then fetch connection details per module on demand.

```dart
final slimSynth = NetlistSynthesizer(
  options: const NetlistOptions(slimMode: true),
);
final slimJson = await slimSynth.synthesizeToJson(myModule);
```

### Using SynthBuilder directly

Just like SystemVerilog synthesis, you can use `SynthBuilder` directly with a `NetlistSynthesizer` for more control:

```dart
final synthesizer = NetlistSynthesizer();
final synth = SynthBuilder(myModule, synthesizer);

// Access individual NetlistSynthesisResult objects
for (final result in synth.synthesisResults) {
    if (result is NetlistSynthesisResult) {
        print('${result.instanceTypeName}: '
              '${result.ports.length} ports, '
              '${result.cells.length} cells');
    }
}

// Or build the combined modules map directly
final modulesMap = await synthesizer.buildModulesMap(synth, myModule);
```

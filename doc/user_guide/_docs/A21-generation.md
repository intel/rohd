---
title: "Generating Outputs"
permalink: /docs/generation/
last_modified_at: 2023-11-13
toc: true
---

Hardware in ROHD is convertible to an output format via `Synthesizer`s, the most popular of which is SystemVerilog. Hardware in ROHD can be converted to logically equivalent, human-readable SystemVerilog with structure, hierarchy, ports, and names maintained.

The simplest way to write SystemVerilog is with `dumpSystemVerilog` on
`Module`:

```dart
void main() async {
    final myModule = MyModule();
    
    // remember that `build` returns a `Future`, hence the `await` here
    await myModule.build();

    myModule.dumpSystemVerilog('myHardware.sv');
}
```

  `dumpSystemVerilog` writes one file containing the SystemVerilog `module`
  definitions for the top-level module and all recursive submodules. To write
  one `.sv` file per module definition instead, pass a directory and set
  `multiFile` to `true`:

  ```dart
  myModule.dumpSystemVerilog('build/systemverilog', multiFile: true);
  ```

  For generated text without writing a file, per-module output, or more advanced
  output controls, use `SystemVerilogService` directly:

  ```dart
  final service = SystemVerilogService(myModule);

  // Use generated text in another tool or inspect a particular definition.
  final generatedSv = service.output;
  final firstGeneratedModule = service.fileContents.first.contents;
  ```

## Controlling port types

Generated ports default to `input logic`, `output logic`, and `inout wire`, preserving the traditional ROHD declarations. Use a `SystemVerilogSynthesizerConfiguration` to independently control whether object types, such as `wire` and `var`, and data types, such as `logic`, are explicit for each port direction:

```dart
myModule.dumpSystemVerilog(
  'myHardware.sv',
  configuration: const SystemVerilogSynthesizerConfiguration(
    inputPortType: SystemVerilogPortTypeConfiguration(
      objectType: SystemVerilogPortType.explicit,
      dataType: SystemVerilogPortType.implicit,
    ),
    outputPortType: SystemVerilogPortTypeConfiguration(
      objectType: SystemVerilogPortType.implicit,
      dataType: SystemVerilogPortType.implicit,
    ),
    inOutPortType: SystemVerilogPortTypeConfiguration(
      objectType: SystemVerilogPortType.implicit,
      dataType: SystemVerilogPortType.explicit,
    ),
  ),
);
```

The same configuration can be passed directly to `SystemVerilogSynthesizer`
when using `SynthBuilder`.

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

`SystemVerilogService` provides access to the underlying synthesis results,
per-module file contents, configurable headers, and named output files. For
custom synthesis flows, [`SynthBuilder`](https://intel.github.io/rohd/rohd/SynthBuilder-class.html)
accepts a `Module` and a `Synthesizer` (usually a
`SystemVerilogSynthesizer`).

## Capturing waveforms

Use `dumpWaveforms` for the common case of writing all simulation signals to a
VCD file:

```dart
myModule.dumpWaveforms(outputPath: 'waves.vcd');
```

For selective capture or other waveform configuration, create a
`WaveformService` directly. Its options are intended for more involved capture
flows and may grow over time:

```dart
WaveformService(
  myModule,
  outputPath: 'interesting-signals.vcd',
  timescale: '1ns',
  startTime: 100,
  stopTime: 1000,
  signalFilter: (signal) => signal.name.startsWith('debug_'),
);
```

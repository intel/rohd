---
title: "Generating Outputs"
permalink: /docs/generation/
last_modified_at: 2023-11-13
toc: true
---

Hardware in ROHD is convertible to an output format via `Synthesizer`s, the most popular of which is SystemVerilog. Hardware in ROHD can be converted to logically equivalent, human readable SystemVerilog with structure, hierarchy, ports, and names maintained.

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
- The `name`, which maps to the instance name when that instance is instanitated as a sub-module of another module.
  - If you want to ensure this does not change (e.g. uniquified because other signals or sub-modules would have the same name), then set `reserveName` to `true`.

### Internal signals

Internal signals, unlike ports, don't need to always have the same exact name as in the original hardware definition.

- If you do not name a signal, it will get a default name.  Generated code will attempt to avoid keeping that intermediate signal around (declared) if possible.
- If you do name a signal, by default it will be characterized as `renameable`.  This means it will try to keep that name in generated output, but may rename it for uniqification purposes.
- If you want to make sure an internal signal maintains exactly the name you want, you can mark it explicitly with `reserved`.
- You can downgrade a named signal as well to `mergeable` or even `unnamed`, if you care less about it's name in generated outputs and prefer that others will take over.

### Unpreferred names

The `Naming.unpreferredName` function will modify a signal name to indicate to downstream flows that the name is preferably omitted from the output, but preferable to an unnamed signal. This is generally most useful for things like output ports of `InlineSystemVerilog` modules.

## More advanced generation

Under the hood of `generateSynth`, it's actually using a [`SynthBuilder`](https://intel.github.io/rohd/rohd/SynthBuilder-class.html) which accepts a `Module` and a `Synthesizer` (usually a `SystemVerilogSynthesizer`) as arguments.  This `SynthBuilder` can provide a collection of `String` file contents via `getFileContents`, or you can ask for the full set of `synthesisResults`, which contains `SynthesisResult`s which can each be converted `toFileContents` but also has context about the `module` it refers to, the `instanceTypeName`, etc. With these APIs, you can easily generate named files, add file headers, ignore generation of some modules, generate file lists for other tools, etc.

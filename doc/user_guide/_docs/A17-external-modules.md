---
title: "External Modules"
permalink: /docs/external-modules/
excerpt: "External Modules"
last_modified_at: 2026-9-1
toc: true
---

ROHD can instantiate external SystemVerilog modules.  The [`ExternalSystemVerilogModule`](https://intel.github.io/rohd/rohd/ExternalSystemVerilogModule-class.html) constructor requires the top level SystemVerilog module name.  When ROHD generates SystemVerilog for a model containing an `ExternalSystemVerilogModule`, it will instantiate instances of the specified `definitionName`.  This is useful for integration related activities.

The [ROHD Cosim](https://github.com/intel/rohd-cosim) package enables SystemVerilog cosimulation with ROHD by adding cosimulation capabilities to an `ExternalSystemVerilogModule`.

## Example

Wrap an existing SystemVerilog module by extending `ExternalSystemVerilogModule`, passing the SV module name as `definitionName`, and declaring the same ports (and optional parameters) that the SV module uses.

Suppose this SystemVerilog module already exists outside of ROHD:

```systemverilog
module external_module_name #(
  parameter WIDTH = 8
) (
  input  [WIDTH-1:0] a,
  output [WIDTH-1:0] b
);
  assign b = a;
endmodule
```

A Dart wrapper can instantiate it from a ROHD hierarchy:

```dart
class MyExternalModule extends ExternalSystemVerilogModule {
  Logic get b => output('b');

  MyExternalModule(Logic a, {int width = 2})
      : super(
            definitionName: 'external_module_name',
            parameters: {'WIDTH': '$width'}) {
    addInput('a', a, width: width);
    addOutput('b', width: width);
  }
}

class TopModule extends Module {
  TopModule(Logic a) {
    a = addInput('a', a, width: a.width);
    MyExternalModule(a);
  }
}
```

`definitionName` must match the SystemVerilog module name exactly.  `parameters` are passed through as named parameter assignments on the generated instance.  ROHD will not emit a `module` definition for `external_module_name`; it only instantiates it.

Building `TopModule` and calling `generateSynth()` produces an instantiation like:

```systemverilog
external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));
```

Connect `addInput` / `addOutput` / `addInOut` names to the SV port names.  Behavioral simulation of the external module itself is not included unless you add a model or use [ROHD Cosim](https://github.com/intel/rohd-cosim).

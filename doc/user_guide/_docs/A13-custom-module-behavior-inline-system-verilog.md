---
title: "Custom module behavior with custom in-line SystemVerilog representation"
permalink: /docs/custom-module-behavior-inline-system-verilog/
excerpt: "Custom module behavior with custom in-line SystemVerilog representation"
last_modified_at: 2024-6-3
toc: true
---

Many of the basic built-in gates in Dart implement custom behavior.  An implementation of the `NotGate` is shown below as an example.  There is different syntax for functions which can be inlined versus those which cannot (the `~` can be inlined).  In this case, the `InlineSystemVerilog` mixin is used, but if it were not inlineable, you could use the `SystemVerilog` mixin instead.  Note that it is mandatory to provide an initial value computation when the module is first created for non-sequential modules.

```dart
/// A gate [Module] that performs bit-wise inversion.
class NotGate extends Module with InlineSystemVerilog {
  /// Name for the input of this inverter.
  late final String _inName;

  /// Name for the output of this inverter.
  late final String _outName;

  /// The input to this [NotGate].
  late final Logic _in = input(_inName);

  /// The output of this [NotGate].
  late final Logic out = output(_outName);

  /// Constructs a [NotGate] with [in_] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic in_, {super.name = 'not'}) {
    _inName = Naming.unpreferredName(in_.name);
    _outName = Naming.unpreferredName('${in_.name}_b');
    addInput(_inName, in_, width: in_.width);
    addOutput(_outName, width: in_.width);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(~_in.value);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    assert(inputs.length == 1, 'Gate has exactly one input.');

    final a = inputs[_inName]!;
    return '~$a';
  }
}
```

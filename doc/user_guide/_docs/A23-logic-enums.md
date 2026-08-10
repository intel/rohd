---
title: "Logic Enums"
permalink: /docs/logic-enums/
excerpt: "Representing enumerable values as hardware signals"
last_modified_at: 2026-08-10
toc: true
---

## Logic Enums

[`LogicEnum<T>`](https://intel.github.io/rohd/rohd/LogicEnum-class.html) is a `Logic` signal constrained to values from a Dart enum. It associates each enum member with a bit-vector encoding and preserves that type information through simulation and SystemVerilog generation.

```dart
enum Operation { idle, read, write }

final operation = LogicEnum(
  Operation.values,
  name: 'operation',
  definitionName: 'Operation',
);
```

The default constructor assigns sequential encodings in the order provided. The width is inferred from the number of values, or it can be set explicitly with `width`.

For sparse or protocol-defined encodings, use `LogicEnum.withMapping`:

```dart
final operation = LogicEnum<Operation>.withMapping(
  {
    Operation.idle: 0,
    Operation.read: 1,
    Operation.write: 3,
  },
  width: 2,
  definitionName: 'Operation',
);
```

Mappings must be non-empty and contain unique, valid, non-negative encodings that fit within the signal width. Reading a valid but unmapped bit pattern in simulation produces `x`.

## Using Enum Values

Enum members can be used directly in conditional assignments to a compatible `LogicEnum`:

```dart
Combinational([
  If(enable, then: [
    operation < Operation.read,
  ], orElse: [
    operation < Operation.idle,
  ]),
]);
```

Use `getsEnum` for a continuous connection to a constant enum value. In testbench code, `put` and `inject` also accept enum members. The current enum member is available through `valueEnum` when the signal contains a mapped value.

```dart
final constantOperation = operation.clone()
  ..getsEnum(Operation.write);

operation.inject(Operation.read);
expect(operation.valueEnum, Operation.read);
```

Assignments between `LogicEnum`s require the same Dart enum type, width, and compatible encodings. A destination may have additional mapped values, but every value mapped by the source must have the same encoding in the destination.

## Cases

Enum members can be used as keys when a `LogicEnum` is the selector:

```dart
final selected = cases(operation, {
  Operation.idle: idleData,
  Operation.read: readData,
  Operation.write: writeData,
});
```

The `cases` helper returns an ordinary `Logic`, so bare enum members are not accepted as result or default values. When an enum result is required, provide explicitly mapped `LogicEnum` branch signals and connect the result to a compatible `LogicEnum` destination.

## Module Ports

Use `addTypedInput` and `addTypedOutput` to preserve an enum's mapping across module boundaries:

```dart
final operationIn = addTypedInput('operationIn', operationSource);
final operationOut = addTypedOutput('operationOut', operationIn.clone);

operationOut <= operationIn;
```

Generated SystemVerilog keeps input and output ports packed and uses internal enum-typed backing signals. Typed `LogicEnum` in/out ports are not supported because `LogicEnum` does not currently have a net-backed variant.

## Generated SystemVerilog

By default, SystemVerilog generation emits enum typedefs and symbolic values for `LogicEnum` signals. The `definitionName` supplies the preferred typedef name, and generated names are uniquified when necessary.

Enum generation can be disabled for tools or flows that require ordinary packed logic:

```dart
final generatedSv = module.generateSynth(
  configuration: const SystemVerilogSynthesizerConfiguration(
    generateEnums: false,
  ),
);
```

Disabling enum generation changes only the generated representation; simulation behavior and the ROHD model remain typed.

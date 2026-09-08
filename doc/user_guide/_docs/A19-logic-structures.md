---
title: "Logic Structures"
permalink: /docs/logic-structures/
last_modified_at: 2026-9-4
toc: true
---

A [`LogicStructure`](https://intel.github.io/rohd/rohd/LogicStructure-class.html) is a useful way to group or bundle related `Logic` signals together. They operate in a similar way to "`packed` `structs`" in SystemVerilog, or a `class` containing multiple `Logic`s in ROHD, but with some important differences.

**`LogicStructure`s will _not_ convert to `struct`s in generated SystemVerilog.** They are purely a way to deal with signals during generation time in ROHD.

**`LogicStructure`s can be used anywhere a `Logic` can be**. This means you can assign one structure to another structure, or inter-assign between normal signals and structures.  As long as the overall width matches, the assignment will work. The order of assignment of bits is based on the order of the `elements` in the structure.

**Elements within a `LogicStructure` can be individually assigned.** This is a notable difference from individual bits of a plain `Logic` where you'd have to use something like `withSet` or `assignSubset` to effectively modify bits within a signal.

Ports with matching types to the original `LogicStructure` can be created using `addTypedInput`, `addTypedOutput`, and `addTypedInOut`.  Note that these functions rely on a proper implementation of the `clone` function.

`LogicArray`s are a type of `LogicStructure` and thus inherit these behavioral traits.

## Type-preserving operations

`StructureMux`, `StructureFlipFlop`, and `StructurePassthrough` preserve a
concrete `LogicStructure` type when their structure operands match:

```dart
final selected = StructureMux(select, packet1, packet0).out;
final registered =
    StructureFlipFlop(clk, selected, reset: reset).q;
final forwarded = StructurePassthrough(registered).out;

// All three values have type Packet.
forwarded.valid <= selected.valid;
```

The same behavior applies to `LogicArray` and `LogicArrayOf<T>`, including nested typed arrays. Both mux operands must have the same concrete type and recursive shape: field widths, array dimensions, and packing hints must match.

Typed operations can consume a structure containing `Const` leaves when its
`clone()` implementation returns the same concrete structure type with
driveable `Logic` leaves. The operation preserves the structure type while
normalizing its input port and output to driveable logic. This supports
domain-specific constant structures, such as a floating-point structure
assembled from constant sign, exponent, and mantissa fields.

The existing `Mux`, `FlipFlop`, and `Passthrough` APIs always produce ordinary
`Logic`. They accept structures as packed inputs when widths match, but do not
preserve named fields:

```dart
final Logic selected = Mux(select, packet1, packet0).out;
final Logic registered = FlipFlop(clk, selected).q;
```

### Case selection

`Case` can assign structures directly because its branches contain ordinary
conditional assignments. The destination determines the result type:

```dart
final selected = packet0.cloneTyped(name: 'selected');

Combinational([
  Case(selector, [
    CaseItem(Const(0, width: selector.width), [selected < packet0]),
    CaseItem(Const(1, width: selector.width), [selected < packet1]),
  ]),
]);
```

Direct structure assignments require matching total widths and map bits in
packed leaf order. They do not require the source and destination to have the
same concrete structure type.

Use `typedCases` when the operation should construct and return a value while
preserving its concrete type:

```dart
final Packet selected = typedCases(
  selector,
  {0: packet0, 1: packet1},
  defaultValue: fallback,
);
```

All structured values passed to `typedCases` must have the same concrete type
and recursive shape. The legacy `cases` helper accepts structures as packed
values but always returns an ordinary `Logic`.

Use `selectIndexTyped` and `selectFromTyped` for structure-preserving indexed
selection. `StructurePipeline<T>` preserves the same concrete type at every
registered pipeline boundary. Specify `T` when creating a pipeline with inline
stage transforms so Dart can type the transform parameter.

## Using `LogicStructure` to group signals

The simplest way to use a `LogicStructure` is to just use its constructor, which requires a collection of `Logic`s.

For example, if you wanted to bundle together a `ready` and a `valid` signal together into one structure, you could do this:

```dart
final rvStruct = LogicStructure([Logic(name: 'ready'), Logic(name: 'valid')]);
```

You could now assign this like any other `Logic` all together:

```dart
Logic ready, valid;
rvStruct <= [ready, valid].rswizzle();
```

Or you can assign individual `elements`:

```dart
rvStruct.elements[0] <= ready;
rvStruct.elements[1] <= valid;
```

## Promoting nested fields

Use `flattenOuter` to promote fields from direct child structures into a new generic `LogicStructure`. The new fields are clones connected to their original sources, so the original structure remains unchanged. By default, promoted names are prefixed with the direct child structure name to avoid collisions.

```dart
final config = LogicStructure([
  Logic(name: 'mode', width: 2),
  Logic(name: 'valid'),
], name: 'config');
final control = LogicStructure([
  Logic(name: 'enable'),
  config,
], name: 'control');

final flattened = control.flattenOuter();
// Field names: enable, config_mode, config_valid.
```

Only direct non-array child structures are promoted. Nested grandchildren remain structures, and a duplicate resulting field name throws `LogicConstructionException`.

## Making your own structure

Referencing elements by index is often not ideal for named signals. We can do better by building our own structure that inherits from `LogicStructure`.

```dart
class ReadyValidStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory ReadyValidStruct({String name = 'readyValid'}) => ReadyValidStruct._(
        Logic(name: 'ready'),
        Logic(name: 'valid'),
        name: name,
      );

  ReadyValidStruct._(this.ready, this.valid, {required String name})
      : super([ready, valid], name: name);

  @override
  ReadyValidStruct clone({String? name}) =>
      ReadyValidStruct(name: name ?? this.name);
}
```

Here we've built a class that has `ready` and `valid` as fields, so we can reference those instead of by element index.  We use some tricks with `factory`s to make this easier to work with.

We override the `clone` function so that we can make a duplicate structure of the same type.

There's a lot more that can be done with a custom class like this, but this is a good start. There are places where it may even make sense to prefer a custom `LogicStructure` to an `Interface`.

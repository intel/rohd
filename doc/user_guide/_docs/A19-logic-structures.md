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

`Mux`, `FlipFlop`, and `Passthrough` preserve a concrete `Logic` subtype when
their operands establish a compatible output representation:

```dart
final selected = Mux(select, packet1, packet0).out;
final registered = FlipFlop(clk, selected, reset: reset).q;
final forwarded = Passthrough(registered).out;

// All three values have type Packet.
forwarded.valid <= selected.valid;
```

The same behavior applies to `LogicArray` and `TypedLogicArray<T, V>`, including
nested typed arrays. A mux uses its `d0` operand as the default output
prototype. Both operands must have matching concrete types and recursive
geometry: field widths, array dimensions, packing hints, and leaf structure.
Pass an `outputGenerator` to `Mux`, `FlipFlop`, `mux`, `flop`, or `cases` to
select a different result representation. Use `Passthrough.withOutput` for
the corresponding pass-through override while retaining the historical
positional `name` argument of `Passthrough`.

These operations can consume a structure containing `Const` leaves when its
`clone()` implementation returns the same concrete structure type with
driveable `Logic` leaves. The operation preserves the structure type while
normalizing its input port and output to driveable logic. This supports
domain-specific constant structures, such as a floating-point structure
assembled from constant sign, exponent, and mantissa fields. Plain `Const` and
`LogicNet` sources cannot infer a driveable result type, so normalize them
explicitly:

```dart
final Logic registered = flop<Logic>(clk, Const(0x5a, width: 8));
```

For a valid constant mux control without an `outputGenerator`, `mux` returns
the selected source directly. Supplying an `outputGenerator` always constructs
a fresh driveable output, including for a constant control.

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

Use generic `cases` when the operation should construct and return a value
while preserving its concrete type:

```dart
final selected = cases(
  selector,
  {0: packet0, 1: packet1},
  defaultValue: fallback,
  outputGenerator: packet0.clone,
);
```

The output generator is also how a structured result can accept deliberately
packed branch values. A packed source is interpreted using the generated
output's representation. Different structured domain types should be converted
to `packed` explicitly before that bit reinterpretation.

Use `selectIndex` and `selectFrom` for structure-preserving indexed selection.
`StructurePipeline<T>` preserves the same concrete type at every
registered pipeline boundary. Specify `T` when creating a pipeline with inline
stage transforms so Dart can type the transform parameter.

### Migrating type-preserving operations

The former `StructureMux`, `StructureFlipFlop`, `StructurePassthrough`,
`typedCases`, `typedMux`, `typedFlop`, `selectIndexTyped`, and
`selectFromTyped` entry points are replaced by the corresponding established
generic APIs. Use `cloneTyped()` and `namedTyped()` when the receiver's static
type should be retained without a cast. `Const.cloneTyped()` remains a literal
clone, while `Const.namedTyped()` is rejected because a named alias is
driveable; use `Const.named()` when an ordinary `Logic` alias is intended.

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

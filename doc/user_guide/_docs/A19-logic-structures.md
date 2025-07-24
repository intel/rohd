---
title: "Logic Structures"
permalink: /docs/logic-structures/
last_modified_at: 2025-7-23
toc: true
---

A [`LogicStructure`](https://intel.github.io/rohd/rohd/LogicStructure-class.html) is a useful way to group or bundle related `Logic` signals together. They operate in a similar way to "`packed` `structs`" in SystemVerilog, or a `class` containing multiple `Logic`s in ROHD, but with some important differences.

**`LogicStructure`s will _not_ convert to `struct`s in generated SystemVerilog.** They are purely a way to deal with signals during generation time in ROHD.

**`LogicStructure`s can be used anywhere a `Logic` can be**. This means you can assign one structure to another structure, or inter-assign between normal signals and structures.  As long as the overall width matches, the assignment will work. The order of assignment of bits is based on the order of the `elements` in the structure.

**Elements within a `LogicStructure` can be individually assigned.** This is a notable difference from individual bits of a plain `Logic` where you'd have to use something like `withSet` or `assignSubset` to effectively modify bits within a signal.

Ports with matching types to the original `LogicStructure` can be created using `addMatchedInput`, `addMatchedOutput`, and `addMatchedInOut`.  Note that these functions rely on a proper implementation of the `clone` function.

`LogicArray`s are a type of `LogicStructure` and thus inherit these behavioral traits.

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

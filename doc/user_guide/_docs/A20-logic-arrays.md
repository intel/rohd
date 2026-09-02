---
title: "Logic Arrays"
permalink: /docs/logic-arrays/
last_modified_at: 2026-09-16
toc: true
---

Use [`LogicArray`](https://intel.github.io/rohd/rohd/LogicArray-class.html)
for multidimensional arrays of ordinary `Logic`. Use
[`TypedLogicArray`](https://intel.github.io/rohd/rohd/TypedLogicArray-class.html)
when each array position has a specialized hardware type and semantic value
type. Both are `LogicStructure`s, so they can be indexed as arrays while still
participating in ordinary packed `Logic` assignments and operations.

`LogicArray`s can be constructed easily using the constructor:

```dart
// A 1D array with ten 8-bit elements.
LogicArray([10], 8);

// A 4x3 2D array, with four arrays, each with three 2-bit elements.
LogicArray([4, 3], 2, name: 'array4x3');

// A 5x5x5 3D array, with 125 total elements, each 128 bits.
LogicArray([5, 5, 5], 128);
```

As long as the total width of a `LogicArray` and another type of `Logic` (including `Logic`, `LogicStructure`, and another `LogicArray`) are the same, assignments and bitwise operations will work in per-element order.  This means you can assign two `LogicArray`s of different dimensions to each other as long as the total width matches.

## Typed arrays

Use `TypedLogicArray<TLogic, TValue>` when every array position has the same
specialized hardware type and associated semantic value type. `LogicArray` is
the ordinary `TypedLogicArray<Logic, LogicValue>` specialization.

For example, these sample hardware and value types preserve named fields in hardware while exposing typed snapshots:

```dart
class Sample extends LogicStructure {
  final Logic data;
  final Logic valid;

  factory Sample({String? name}) => Sample._(
        Logic(name: 'data', width: 8),
        Logic(name: 'valid'),
        name: name ?? 'sample',
      );

  Sample._(this.data, this.valid, {required String name})
      : super([data, valid], name: name);

  @override
  Sample clone({String? name}) => Sample(name: name ?? this.name);
}

class SampleValue {
  final LogicValue value;

  SampleValue(this.value);
}

SampleValue decodeSample(LogicValue value) => SampleValue(value);
LogicValue encodeSample(SampleValue value) => value.value;

const sampleCodec = LogicValueCodec<SampleValue>(
  decode: decodeSample,
  encode: encodeSample,
);

final samples = TypedLogicArray<Sample, SampleValue>(
  [2, 3],
  Sample.new,
  valueCodec: sampleCodec,
);

final bottomRightData = samples.at([1, 2]).data;
final TypedLogicValueArray<SampleValue> currentSamples = samples.value;
```

The element builder must consistently produce the configured type, width,
ordered structure, and net kind. Every element must be entirely variable or
entirely net; a structure cannot mix `Logic` and `LogicNet` leaves. Use
`elementCompatibility` when equal width is not enough to establish compatible
representations.

`valueCodec` is optional only when `TValue` is `LogicValue`. A custom codec
should decode every four-state value that can appear in its hardware.
`dimensionNames` controls child naming during construction and cloning; it is
not public axis metadata. See the
[`TypedLogicArray` API documentation](https://intel.github.io/rohd/rohd/TypedLogicArray-class.html)
for the complete constructor and cloning contracts.

Hardware shape changes should use ordinary construction and connection APIs rather than specialized typed-array adapters. Construct a new `TypedLogicArray` with the desired dimensions and builder, then connect it with `gets`/`<=` when row-major assignment is sufficient. For a transpose, connect corresponding coordinates explicitly with `indexedElements` and `at`; whole-array assignment does not infer a permutation. This keeps construction disconnected and leaves driver ownership with the caller.

### Traversal boundaries

These APIs intentionally stop at different boundaries:

- `elements` contains the immediate children of the outermost structure or array level.
- `TypedLogicArray<TLogic, TValue>.arrayElements` traverses exactly the dimensions declared by that array and then stops at `TLogic`. It is an unmodifiable `List<TLogic>`.
- `indexedElements` pairs those same typed array elements with their row-major multidimensional indices.
- `at(indices)` returns one typed array element.
- `leafElements` recursively traverses every nested array and structure until it reaches non-structure signals.

For example, a `[2, 3]` array of two-field `Sample`s has six `arrayElements` and twelve recursive `leafElements`. A `[2]` array whose elements are `[3]` arrays has two `arrayElements` and six recursive leaves. An eight-bit `Logic` is one leaf, not eight.

A `TypedLogicArray` element can be a `LogicStructure`, but it must be driveable.
Direct `Const` elements and structures containing a `Const` are rejected.
Nested arrays are supported for ROHD construction, packed assignment, and
`arrayElements`, `at`, and `indexedElements` traversal.

At a generated SystemVerilog boundary, a nested array-valued element may occupy
packed bits within its containing element rather than introduce another visible
array dimension. Its row-major value and structure-field order are preserved;
use `at`, `indexedElements`, and named fields in ROHD instead of depending on
the textual shape of generated selections.

Some simulators do not accept unpacked `inout` array ports. Prefer packed
outer dimensions for portable bidirectional interfaces.

Zero-sized arrays are supported for simulation and value operations.
SystemVerilog generation rejects them because the language has no portable
zero-width array declaration.

Icarus Verilog 12.0 can leave child-driven unpacked array variables unknown
during simulation. When targeting that tool, enable
`SystemVerilogSynthesizerConfiguration.iverilogWorkaroundForUnpackedArrayVariables`.

See the [`TypedLogicArray` API documentation](https://intel.github.io/rohd/rohd/TypedLogicArray-class.html)
for subclassing and cloning details.

## Value-domain arrays

Use `LogicValueArray` for fixed-width array data outside the hardware graph.
Nested lists are the ordinary construction form and describe the shape
directly. Flat row-major values use an explicitly named `fromFlat` constructor
with shape metadata:

```dart
final values = LogicValueArray.fromInts(
  [
    [1, 2, 3],
    [4, 5, 6],
  ],
  elementWidth: 8,
);
final sameValues = LogicValueArray.fromFlatInts(
  [2, 3],
  [1, 2, 3, 4, 5, 6],
  elementWidth: 8,
);
final emptyRows =
    LogicValueArray.fromFlat([2, 0], const [], elementWidth: 8);

final transposed = values.transpose2D(); // Dimensions: [3, 2]
final signals = values.toLogicArray(name: 'values'); // signals are driven by values
```

Nested lists infer shape and reject ragged or inconsistent input. Use `fromFlat`
for row-major data, empty arrays, or list-valued semantic elements whose
nesting would be ambiguous. Empty input needs explicit dimensions and element
width. `stack` requires arrays to share the same codec instance.

Decoded semantic values are exposed by reference; mutating a mutable value does
not update its packed bits, so immutable semantic values are usually the
simplest choice. Both value-array types retain packed `LogicValue` behavior:
same-width assignment is based on packed bits, not shape. See the
[`LogicValueArray`](https://intel.github.io/rohd/rohd/LogicValueArray-class.html)
and
[`TypedLogicValueArray`](https://intel.github.io/rohd/rohd/TypedLogicValueArray-class.html)
API documentation for codec normalization, shape operations, packed-value
semantics, and snapshots.

## Unpacked arrays

In SystemVerilog, there is a concept of "packed" vs. "unpacked" arrays which have different use cases and capabilities. In ROHD, all arrays act the same and you get the best of both worlds.  You can indicate when constructing a `LogicArray` that some number of the dimensions should be "unpacked" as a hint to `Synthesizer`s. Marking an array with a non-zero `numUnpackedDimensions`, for example, will make that many of the dimensions "unpacked" in generated SystemVerilog signal declarations.

```dart
// A 4x3 2D array, with four arrays, each with three 2-bit elements.
// The first dimension (4) will be unpacked.
LogicArray(
  [4, 3],
  2,
  name: 'array4x3w1unpacked',
  numUnpackedDimensions: 1,
);
```

## Array ports

You can declare ports of `Module`s as being arrays (including with some dimensions "unpacked") using `addInputArray` and `addOutputArray`. Note that these do _not_ automatically do validation that the dimensions, element width, number of unpacked dimensions, etc. are equal between the port and the original signal. As long as the overall width matches, the assignment will be clean.

Array ports in generated SystemVerilog will match dimensions (including unpacked) as specified when the port is created.

Use the existing `addTypedInput`, `addTypedOutput`, and `addTypedInOut` methods for `TypedLogicArray` ports. Their generic `LogicType` preserves the complete array subtype, including its hardware element type, semantic value type, codec, net kind, dimensions, and unpacked-dimension configuration. This allows the module to access fields such as `samples.at([1, 2]).data` directly. The established `addInputArray`, `addOutputArray`, and `addInOutArray` APIs remain the concrete `LogicArray` helpers.

## Type-preserving operations

`LogicArray` and `LogicArrayOf<T>` can be used with `Mux`, `FlipFlop`, and `Passthrough`. The output retains the array's concrete type, dimensions, and specialized leaf type:

```dart
final selected = Mux(select, samplesA, samplesB).out;
final delayed = FlipFlop(clk, selected, reset: reset).q;
final forwarded = Passthrough(delayed).out;

final bottomRightData = forwarded.elementAt([1, 2]).data;
```

The mux inputs must have matching concrete array types and geometry, including dimensions, leaf widths, packed/unpacked configuration, and leaf structure. Use `typedCases`, `selectIndexTyped`, or `selectFromTyped` when selecting one complete typed array from multiple choices. Specify the array type parameter on `StructurePipeline<T>` when its stages use inline transforms.

## Elements of arrays

Use `elements` to inspect immediate children, `arrayElements` or `indexedElements` to traverse declared array positions, and `leafElements` only when fully recursive traversal is intended. The normal `[n]` operator selects the `n`th packed bit for both `LogicArray` and `Logic`; use `at` for multidimensional typed element indexing.

## Index-based Selection in an Array

The [`selectIndex`](https://intel.github.io/rohd/rohd/IndexedLogic/selectIndex.html) and [`selectFrom`](https://intel.github.io/rohd/rohd/Logic/selectFrom.html) methods are used to select a value from a `LogicArray` or from a list of `Logic` elements based on an index. These methods are useful for creating dynamic selection logic in hardware design. They can be used in 2 ways as shown below.

### 1. Using a `LogicArray` type

```dart
final arrayA = LogicArray([4], 8, name: 'arrayA'); // A 1D array with four 8-bit element
final id = Logic(name: 'id', width: 3);

selectIndexValueArrayA <= arrayA.elements.selectIndex(id, defaultValue: defaultValue);
selectFromValueArrayA <= id.selectFrom(arrayA.elements, defaultValue: defaultValue);
```

An example code is given to demonstrate a usage of `selectIndex` and `selectFrom` for logic arrays.
Please see code here: [logic_array.dart](https://github.com/intel/rohd/blob/main/example/logic_array.dart)

### 2. Using a list of `Logic` elements

```dart
final inputA = Logic(name: 'inputA', width: 8);
final inputB = Logic(name: 'inputB', width: 8);
final inputC = Logic(name: 'inputC', width: 8);
final listA = <Logic>[inputA, inputB, inputC];

final id = Logic(name: 'id', width: 3);

selectIndexValueListA <= listA.selectIndex(id, defaultValue: defaultValue);
selectFromValueListA <= id.selectFrom(listA, defaultValue: defaultValue);
```

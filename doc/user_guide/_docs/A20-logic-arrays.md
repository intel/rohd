---
title: "Logic Arrays"
permalink: /docs/logic-arrays/
last_modified_at: 2026-09-10
toc: true
---

A [`LogicArray`](https://intel.github.io/rohd/rohd/LogicArray-class.html) is a type of `LogicStructure` that mirrors multi-dimensional arrays in hardware languages like SystemVerilog. `TypedLogicArray` uses the same structural model. An array is not a scalar `Logic` with an internal wire sliced into elements: it owns a hierarchy of child signals. `LogicStructure` supplies the common `Logic` behavior by packing those children when a scalar-like operation is needed, while the array layer adds dimensions, array-boundary traversal, and indexing. `TypedLogicArray` is indirectly a `Logic` through `LogicStructure`. `LogicArray` directly extends `TypedLogicArray<Logic, LogicValue>` as its ordinary-`Logic` specialization and inherits the typed-array API.

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

Use `TypedLogicArray<TLogic, TValue>` when every position at the declared array boundary has the same specialized hardware type and associated semantic value type. `LogicArray` directly extends `TypedLogicArray<Logic, LogicValue>` as the ordinary specialization, inheriting its array metadata, traversal, indexing, and assignment APIs while preserving its existing constructors and concrete clone and naming behavior. `TypedLogicArray` extends the non-generic `BaseLogicArray`, which is an internal implementation base rather than another public construction API.

`dimensionNames`, when supplied to `TypedLogicArray`, is construction metadata used to derive names within typed-array hierarchies and preserve them during internal cloning. It is not a public axis-metadata property, and it does not change the established generated naming convention of ordinary `LogicArray`.

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

The element builder must always produce the configured type, width, and recursively ordered net composition. Every element must be uniformly variable or uniformly net: a structure cannot mix `Logic` and `LogicNet` leaves. The optional `elementCompatibility` callback can additionally reject elements whose semantic representations differ from the prototype, such as floating-point elements with different exponent and mantissa layouts despite having the same total width.

A zero-sized array calls the builder once as a prototype so that the same metadata and validation remain available even though the array has no positions. Generic zero-sized arrays retain the prototype's element width; `LogicArray` retains its historical behavior of reporting an element width of zero for an empty shape.

`valueCodec` may be omitted when `TValue` is exactly `LogicValue`; the canonical identity codec is selected automatically. Other semantic types require a codec. Since hardware may contain `X` and `Z`, a codec used by `TypedLogicArray` should decode every four-state value that can appear in that hardware.

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

SystemVerilog declarations retain the packed/unpacked split of the root array.
When a configured element contains another array, that nested value occupies
packed bits within the root element at the port boundary. Nested coordinates
and structure fields are therefore lowered to one packed bit or range selection
instead of adding dimensions that are absent from the declaration. An
array-valued structure field may use a separate internal declaration with its
own packed/unpacked split; synthesis inserts the packing or unpacking needed at
the enclosing port.

This lowering preserves the existing inline declaration and naming style; it
does not introduce SystemVerilog `typedef`s or generated structural type names.
Whole assignments involving nested unpacked arrays are emitted as element or
packed-range assignments for simulator portability. The netlist output retains
the recursive array and structure metadata in `logic_type`.

ROHD, Icarus, and Verilator simulation cover fully packed nested arrays,
mixed packed/unpacked outer and inner arrays, and structures containing
unpacked ordinary and typed array fields across module boundaries. Four-state
structured inout drive and release, including an unpacked nested net-array
field across a child boundary, is covered in ROHD and Icarus. Verilator does
not currently simulate that last case because it does not support the
bidirectional `tran` primitive used for net aliasing.

`TypedLogicArray` is also the supported base for custom typed arrays. Subclasses should use the normal constructor and override `createClone` to preserve their runtime type and metadata. Constructor-only configuration needed during reconstruction, including custom `dimensionNames`, should be retained in private subclass fields and passed back through the subclass constructor. The lower-level prebuilt-element constructor is library-private and is reserved for trusted in-library construction.

## Value-domain arrays

Use `LogicValueArray` for fixed-width array data outside the hardware graph. Nested lists are the ordinary construction form and describe the shape directly. Flat row-major values use an explicitly named `fromFlat` constructor with shape metadata:

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

Nested constructors reject ragged rows, inconsistent nesting depth, and mismatched element widths. Empty nested input cannot reveal the element width or trailing dimensions, so it must use `fromFlat`. `majorSlices` iterates the outer dimension rather than the total element count, so a `[2, 0]` value contains two empty `[0]` slices and can round-trip through `stack`.

`TypedLogicValueArray<T>` adds a `LogicValueCodec<T>` for application-level values. `LogicValueArray` remains its `TypedLogicValueArray<LogicValue>` specialization with the existing convenience constructors and concrete transform return types. Construction immediately encodes and decodes every value: the packed representation is authoritative, and a lossy codec therefore exposes normalized semantic values from the start. Decoded semantic elements are exposed by reference, so mutating a mutable element does not update the stored packed bits; callers using mutable semantic values are responsible for treating them consistently with snapshot semantics. Shape-only operations preserve those normalized values without re-encoding them. `stack` requires every typed value array to use the identical codec object because codec functions cannot be compared for semantic equivalence.

The root list of a nested constructor always represents an array dimension. Below the root, an object matching `T` is treated as one semantic value before it is considered as another list dimension. This permits list-valued semantic elements; use `fromFlat` when the intended interpretation would otherwise be ambiguous.

Both value-array classes are `LogicValue`s. Their `width` and deprecated `length` count packed bits, while `arrayValues.length` counts array positions. `arrayValues` has one entry for each configured array position in row-major order. Bit indexing, equality, hashing, arithmetic, and bitwise operations use the packed value and do not consider shape. The `packed` getter exposes the ordinary `LogicValue` representation.

`TypedLogicArray<TLogic, TValue>.value` and `previousValue` return `TypedLogicValueArray<TValue>` snapshots without adding hardware to the graph. `LogicArray` overrides these with the concrete `LogicValueArray` return type. The standard `changed`, `glitch`, and edge APIs remain packed `LogicValueChanged` events, so typed arrays retain the normal `Logic` event contract. Since all value arrays are `LogicValue`s, use the target-side `put` API for immediate assignment or `inject` for scheduled assignment. Both follow the ordinary packed-value contract, so same-width values remain assignable regardless of their shape metadata.

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

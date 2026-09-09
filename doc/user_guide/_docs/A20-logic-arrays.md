---
title: "Logic Arrays"
permalink: /docs/logic-arrays/
last_modified_at: 2026-9-9
toc: true
---

A [`LogicArray`](https://intel.github.io/rohd/rohd/LogicArray-class.html) is a type of `LogicStructure` that mirrors multi-dimensional arrays in hardware languages like SystemVerilog.  In ROHD, the `LogicArray` type inherits a lot of functionality from `LogicStructure`, so it can behave like a `Logic` where it makes sense or be individually referenced in other places.

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

Use `LogicArrayOf<T>` when every position at the declared array boundary has the same specialized `Logic` type. `LogicArray` is the ordinary `LogicArrayOf<Logic>` specialization, so existing `LogicArray` construction, port, clone, naming, and array behavior is retained. For example, this creates a two-dimensional array of samples with separate data and valid fields:

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

final samples = LogicArrayOf<Sample>(
  [2, 3],
  Sample.new,
  dimensionNames: ['row_', 'column_'],
);

final bottomRightData = samples.at([1, 2]).data;
```

The element builder must always produce the configured type, width, and recursively ordered net composition. Every element must be uniformly variable or uniformly net: a structure cannot mix `Logic` and `LogicNet` leaves. A zero-sized array calls the builder once as a prototype so that the same metadata and validation remain available even though the array has no positions.

### Traversal boundaries

These APIs intentionally stop at different boundaries:

- `elements` contains the immediate children of the outermost structure or array level.
- `LogicArrayOf<T>.arrayElements` traverses exactly the dimensions declared by that array and then stops at `T`. It is an unmodifiable `List<T>`.
- `indexedElements` pairs those same typed array elements with their row-major multidimensional indices.
- `at(indices)` returns one typed array element.
- `leafElements` recursively traverses every nested array and structure until it reaches non-structure signals.

For example, a `[2, 3]` array of two-field `Sample`s has six `arrayElements` and twelve recursive `leafElements`. A `[2]` array whose elements are `[3]` arrays has two `arrayElements` and six recursive leaves. An eight-bit `Logic` is one leaf, not eight.

When typed array elements are themselves arrays, use `flattenNestedDimensions<U>()` to create one rectangular `LogicArrayOf<U>` with all nested dimensions concatenated. The full address is preserved: `nested.at(outerIndices).at(innerIndices)` maps to `flattened.at([...outerIndices, ...innerIndices])`. Every sibling nested array must have matching dimensions, element width, depth, and unpacked-dimension configuration. Empty shapes are supported because the configured element builders supply the missing metadata.

A `LogicArrayOf` element can be a `LogicStructure`, but it must be driveable. Direct `Const` elements, structures containing a `Const`, and element structures containing nested arrays are rejected. An array can instead directly contain another array and then be flattened as described above.

`LogicArrayOf` is also the supported base for custom typed arrays. A subclass using the protected `LogicArrayOf.structured` constructor must supply a correctly configured element builder and should override `createClone` to preserve its runtime type and metadata.

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
  8,
  [1, 2, 3, 4, 5, 6],
);
final emptyRows = LogicValueArray.fromFlat([2, 0], 8, const []);

final transposed = values.transpose2D(); // Dimensions: [3, 2]
final signals = values.toLogicArray(name: 'values');
```

Nested constructors reject ragged rows, inconsistent nesting depth, and mismatched element widths. Empty nested input cannot reveal the element width or trailing dimensions, so it must use `fromFlat`. `majorSlices` iterates the outer dimension rather than the total element count, so a `[2, 0]` value contains two empty `[0]` slices and can round-trip through `stack`.

`LogicValueArrayOf<T>` adds a `LogicValueCodec<T>` for application-level values. Construction immediately encodes and decodes every value: the packed representation is authoritative, and a lossy codec therefore exposes normalized semantic values from the start. Shape-only operations preserve those normalized values without re-encoding them. `stack` requires every typed value array to use the identical codec object because codec functions cannot be compared for semantic equivalence.

The root list of a nested constructor always represents an array dimension. Below the root, an object matching `T` is treated as one semantic value before it is considered as another list dimension. This permits list-valued semantic elements; use `fromFlat` when the intended interpretation would otherwise be ambiguous.

Both value-array classes are `LogicValue`s. Their `width` and deprecated `length` count packed bits, while `elementCount` counts array positions. Bit indexing, equality, hashing, arithmetic, and bitwise operations use the packed value and do not consider shape. The `packed` getter exposes the ordinary `LogicValue` representation.

`LogicArrayOf.value` captures a `LogicValueArray` without adding hardware to the graph. A compatible shaped value can drive a hardware array through `put`, `inject`, or `putInto`; ordinary same-width packed `LogicValue` assignment remains supported.

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

Use `addTypedInput` and `addTypedOutput` for `LogicArrayOf` ports. These methods preserve the array's specialized leaf type, net kind, dimensions, and unpacked-dimension configuration, allowing the module to access fields such as `samples.at([1, 2]).data` directly. Net-typed leaves are also accepted by typed inout ports.

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

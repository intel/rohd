// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// array_collapsing_test.dart
// Tests for array collapsing
//
// 2024 June 5
// Author: Shankar Sharma <shankar.sharma@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import 'logic_array_test.dart';

class ArrayModule extends Module {
  ArrayModule(LogicArray a) {
    final inpA = addInputArray('a', a, dimensions: a.dimensions);
    addOutputArray('b', dimensions: a.dimensions) <= inpA;

    final inoutA = addInOutArray('c', a, dimensions: a.dimensions);
    addOutputArray('d', dimensions: [a.dimensions.last]) <=
        inoutA.elements.first;
  }
}

class ArrayTopMod extends Module {
  ArrayTopMod(Logic clk) {
    clk = addInput('clk', clk);

    final intermediate =
        LogicArray([4], 1, name: 'asdf', naming: Naming.mergeable);
    final arrOut = ArraySubModOut(clk).arrOut;
    for (var i = 0; i < intermediate.width; i++) {
      final idx = (i + 1) % intermediate.width;
      intermediate.elements[idx] <= arrOut.elements[idx];
    }
    ArraySubModIn(clk, intermediate);
  }
}

class ArraySubModIn extends Module {
  ArraySubModIn(Logic clk, LogicArray inp) {
    clk = addInput('clk', clk);
    addInputArray('inp', inp, dimensions: [4]);
  }
}

class ArraySubModOut extends Module {
  LogicArray get arrOut => output('arrOut') as LogicArray;
  ArraySubModOut(Logic clk) {
    clk = addInput('clk', clk);
    addOutputArray('arrOut', dimensions: [4]);
  }
}

class ArrayWithShuffledAssignment extends Module {
  ArrayWithShuffledAssignment(LogicArray a) {
    final inpA = addInputArray('a', a, dimensions: a.dimensions);
    final outB = addOutputArray('b', dimensions: a.dimensions);

    for (var i = 0; i < a.dimensions.first; i++) {
      outB.elements[i] <= inpA.elements[a.dimensions.first - i - 1];
    }
  }
}

/// Partially assigns three elements of an internal array from an input array.
///
/// When reversed is false, the assignments are contiguous and same-offset,
/// so they can collapse into a range-to-range assignment.  When reversed is
/// true, the assignments are intentionally not same-offset and must remain
/// expanded.
class PartialArrayRangeAssignment extends Module {
  PartialArrayRangeAssignment({bool reversed = false})
      : super(name: 'partial_array_range_assignment') {
    final src = addInputArray('src', LogicArray([6], 1), dimensions: [6]);
    final dst = LogicArray([6], 1, name: 'dst');

    for (var dstIndex = 2; dstIndex <= 4; dstIndex++) {
      final srcIndex = reversed ? 6 - dstIndex : dstIndex;
      dst.elements[dstIndex] <= src.elements[srcIndex];
    }

    addOutput('y', width: 6) <= dst.elements.rswizzle();
  }
}

/// Partially assigns a range through an intermediate array.  The two range
/// assignments should compose so the intermediate array can be pruned.
class ChainedPartialArrayRangeAssignment extends Module {
  ChainedPartialArrayRangeAssignment({
    bool exposeIntermediate = false,
    Naming? intermediateNaming = Naming.mergeable,
  }) : super(name: 'chained_partial_array_range_assignment') {
    final src = addInputArray('src', LogicArray([6], 1), dimensions: [6]);
    final intermediate =
        LogicArray([6], 1, name: 'intermediate', naming: intermediateNaming);
    final dst = LogicArray([6], 1, name: 'dst');

    for (var index = 2; index <= 4; index++) {
      intermediate.elements[index] <= src.elements[index];
      dst.elements[index] <= intermediate.elements[index];
    }

    addOutput('y', width: 6) <= dst.elements.rswizzle();
    if (exposeIntermediate) {
      addOutput('z', width: 6) <= intermediate.elements.rswizzle();
    }
  }
}

/// Partially assigns a range through two intermediate arrays.  The range
/// composition pass should iterate until both intermediates are gone.
class ThreeDeepChainedPartialArrayRangeAssignment extends Module {
  ThreeDeepChainedPartialArrayRangeAssignment()
      : super(name: 'three_deep_chained_partial_array_range_assignment') {
    final src = addInputArray('src', LogicArray([6], 1), dimensions: [6]);
    final intermediate0 =
        LogicArray([6], 1, name: 'intermediate0', naming: Naming.mergeable);
    final intermediate1 =
        LogicArray([6], 1, name: 'intermediate1', naming: Naming.mergeable);
    final dst = LogicArray([6], 1, name: 'dst');

    for (var index = 2; index <= 4; index++) {
      intermediate0.elements[index] <= src.elements[index];
      intermediate1.elements[index] <= intermediate0.elements[index];
      dst.elements[index] <= intermediate1.elements[index];
    }

    addOutput('y', width: 6) <= dst.elements.rswizzle();
  }
}

/// Partially assigns an offset source range through an intermediate, then reads
/// only a subrange of the intermediate.
class ChainedSubrangeArrayRangeAssignment extends Module {
  ChainedSubrangeArrayRangeAssignment()
      : super(name: 'chained_subrange_array_range_assignment') {
    final src = addInputArray('src', LogicArray([8], 1), dimensions: [8]);
    final intermediate =
        LogicArray([8], 1, name: 'intermediate', naming: Naming.mergeable);
    final dst = LogicArray([8], 1, name: 'dst');

    for (var index = 1; index <= 5; index++) {
      intermediate.elements[index] <= src.elements[index + 2];
    }
    for (var index = 2; index <= 3; index++) {
      dst.elements[index] <= intermediate.elements[index + 1];
    }

    addOutput('y', width: 8) <= dst.elements.rswizzle();
  }
}

/// Partially assigns array elements from bits of a flat input bus.
class PartialBusToArrayRangeAssignment extends Module {
  PartialBusToArrayRangeAssignment({
    bool reversed = false,
    int numUnpackedDimensions = 0,
  }) : super(name: 'partial_bus_to_array_range_assignment') {
    final src = addInput('src', Logic(width: 8), width: 8);
    final dst = LogicArray([8], 1,
        name: 'dst', numUnpackedDimensions: numUnpackedDimensions);

    for (var dstIndex = 2; dstIndex <= 5; dstIndex++) {
      final srcIndex = reversed ? 7 - dstIndex : dstIndex;
      dst.elements[dstIndex] <= src[srcIndex];
    }

    addOutput('y', width: 8) <= dst.leafElements.rswizzle();
  }
}

/// Assigns a full array range into a flat bus through [Logic.assignSubset].
class ArrayToBusAssignSubsetRangeAssignment extends Module {
  ArrayToBusAssignSubsetRangeAssignment({bool partial = false})
      : super(name: 'array_to_bus_assign_subset_range_assignment') {
    final src = addInputArray('src', LogicArray([8], 1), dimensions: [8]);
    final dst = Logic(width: 8, name: 'dst');

    final start = partial ? 2 : 0;
    final end = partial ? 5 : 7;
    for (var index = start; index <= end; index++) {
      dst.assignSubset([src.elements[index]], start: index);
    }

    addOutput('y', width: 8) <= dst;
  }
}

/// Assigns a flat bus range into another flat bus through a temporary slice.
class BusSliceTemporaryToAssignSubsetRangeAssignment extends Module {
  BusSliceTemporaryToAssignSubsetRangeAssignment({
    bool receiverIsOutput = false,
    bool driveLowBits = true,
  }) : super(name: 'bus_slice_temporary_to_assign_subset_range_assignment') {
    final src = addInput('src', Logic(width: 16), width: 16);
    final dst = receiverIsOutput
        ? addOutput('y', width: 8)
        : Logic(width: 8, name: 'dst');
    final srcSlice =
        Logic(width: 4, name: 'src_slice', naming: Naming.mergeable);

    if (driveLowBits) {
      for (var index = 0; index < 4; index++) {
        dst.assignSubset([src[index]], start: index);
      }
    }
    srcSlice <= src.getRange(11, 15);
    for (var index = 0; index < 4; index++) {
      dst.assignSubset([srcSlice[index]], start: index + 4);
    }

    if (!receiverIsOutput) {
      addOutput('y', width: 8) <= dst;
    }
  }
}

/// Uses the same selected bus bits both for [Logic.assignSubset] and for other
/// submodule inputs.  Range collapse must not delete the bit-select helpers
/// needed by those other consumers.
class BusSubsetBitsWithExtraConsumers extends Module {
  BusSubsetBitsWithExtraConsumers()
      : super(name: 'bus_subset_bits_with_extra_consumers') {
    final src = addInput('src', Logic(width: 8), width: 8);
    final dst = Logic(width: 4, name: 'dst');
    final inverted = <Logic>[];

    for (var index = 0; index < 4; index++) {
      final selected = src[index + 2];
      dst.assignSubset([selected], start: index);
      inverted.add(InverterMod(selected).o);
    }

    addOutput('y', width: 4) <= dst;
    addOutput('z', width: 4) <= inverted.rswizzle();
  }
}

/// Assigns two sparse contiguous bus ranges into a flat bus through
/// [Logic.assignSubset].
class SparseBusRunsToAssignSubsetRangeAssignment extends Module {
  SparseBusRunsToAssignSubsetRangeAssignment()
      : super(name: 'sparse_bus_runs_to_assign_subset_range_assignment') {
    final srcA = addInput('srcA', Logic(width: 32), width: 32);
    final srcB = addInput('srcB', Logic(width: 16), width: 16);
    final dst = Logic(width: 64, name: 'dst');

    for (var index = 0; index < 12; index++) {
      dst.assignSubset([srcA[index + 4]], start: index + 20);
    }
    for (var index = 0; index < 12; index++) {
      dst.assignSubset([srcB[index]], start: index + 44);
    }

    addOutput('y', width: 64) <= dst;
  }
}

/// Assigns contiguous direct and temporary-sliced bus ranges from an internal
/// source into a flat bus through [Logic.assignSubset].
class InternalBusRunsToAssignSubsetRangeAssignment extends Module {
  InternalBusRunsToAssignSubsetRangeAssignment({bool computedSource = false})
      : super(name: 'internal_bus_runs_to_assign_subset_range_assignment') {
    final src = addInput('src', Logic(width: 32), width: 32);
    final srcStage =
        Logic(width: 32, name: 'srcStage', naming: Naming.mergeable);
    final srcLow = Logic(width: 8, name: 'srcLow', naming: Naming.mergeable);
    final srcHigh = Logic(width: 16, name: 'srcHigh', naming: Naming.mergeable);
    final dst = Logic(width: 64, name: 'dst');

    srcStage <= (computedSource ? ~src : src);
    for (var index = 0; index < 8; index++) {
      dst.assignSubset([srcStage[index]], start: index + 13);
    }
    srcLow <= srcStage.getRange(8, 16);
    for (var index = 0; index < 8; index++) {
      dst.assignSubset([srcLow[index]], start: index + 21);
    }
    srcHigh <= srcStage.getRange(16, 32);
    for (var index = 0; index < 16; index++) {
      dst.assignSubset([srcHigh[index]], start: index + 29);
    }

    addOutput('y', width: 64) <= dst;
  }
}

/// Partially assigns a contiguous run from a temporary slice while also using
/// one bit of that slice elsewhere.  The run should collapse, but the slice
/// helper must remain live for the extra consumer.
class PartialSliceWithExtraConsumer extends Module {
  PartialSliceWithExtraConsumer()
      : super(name: 'partial_slice_with_extra_consumer') {
    final src = addInput('src', Logic(width: 16), width: 16);
    final enable = addInput('enable', Logic());
    final slice = Logic(width: 8, name: 'slice', naming: Naming.mergeable);
    final dst = Logic(width: 12, name: 'dst');

    slice <= src.getRange(4, 12);
    for (var index = 2; index <= 5; index++) {
      dst.assignSubset([slice[index]], start: index + 3);
    }

    addOutput('y', width: 12) <= dst;
    addOutput('z') <= enable & ~slice[3];
  }
}

/// Assigns a temporary flat bus slice into wide array elements.
class WideTemporarySliceToArrayWords extends Module {
  WideTemporarySliceToArrayWords({bool extraConsumers = false})
      : super(name: 'wide_temporary_slice_to_array_words') {
    final src = addInput('src', Logic(width: 128), width: 128);
    final srcSlice =
        Logic(width: 64, name: 'src_slice', naming: Naming.mergeable);
    final dst = addOutputArray('y', dimensions: [4], elementWidth: 16);
    final inverted = <Logic>[];

    srcSlice <= src.getRange(32, 96);
    final words = [
      srcSlice.getRange(0, 16),
      srcSlice.getRange(16, 32),
      srcSlice.getRange(32, 48),
      srcSlice.getRange(48, 64),
    ];
    dst.elements[1] <= words[1];
    dst.elements[0] <= words[0];
    dst.elements[2] <= words[2];
    dst.elements[3] <= words[3];

    if (extraConsumers) {
      for (final word in words) {
        inverted.add(InverterMod(word, width: 16).o);
      }
      addOutput('z', width: 64) <= inverted.rswizzle();
    }
  }
}

/// Uses a manually-created array with a subset-like name.
class ManualSubsetNamedArrayRangeAssignment extends Module {
  ManualSubsetNamedArrayRangeAssignment()
      : super(name: 'manual_subset_named_array_range_assignment') {
    final src = addInputArray('src', LogicArray([6], 1), dimensions: [6]);
    final intermediate =
        LogicArray([6], 1, name: 'manual_subset', naming: Naming.unnamed);

    for (var index = 2; index <= 4; index++) {
      intermediate.elements[index] <= src.elements[index];
    }

    addOutput('y', width: 6) <= intermediate.elements.rswizzle();
  }
}

/// Partially assigns a packed inner dimension of a two-dimensional array.
class PartialInnerArrayRangeAssignment extends Module {
  PartialInnerArrayRangeAssignment({int numUnpackedDimensions = 0})
      : super(name: 'partial_inner_array_range_assignment') {
    final src = addInputArray(
      'src',
      LogicArray([2, 4], 1, numUnpackedDimensions: numUnpackedDimensions),
      dimensions: [2, 4],
      numUnpackedDimensions: numUnpackedDimensions,
    );
    final dst = LogicArray([2, 4], 1,
        name: 'dst', numUnpackedDimensions: numUnpackedDimensions);

    final srcRow = src.elements[1] as LogicArray;
    final dstRow = dst.elements[1] as LogicArray;
    for (var index = 1; index <= 3; index++) {
      dstRow.elements[index] <= srcRow.elements[index];
    }

    addOutput('y', width: 8) <= dst.leafElements.rswizzle();
  }
}

/// Partially assigns an unpacked one-dimensional array, which must not be
/// collapsed into a packed slice.
class PartialUnpackedArrayRangeAssignment extends Module {
  PartialUnpackedArrayRangeAssignment()
      : super(name: 'partial_unpacked_array_range_assignment') {
    final src = addInputArray(
      'src',
      LogicArray([6], 1, numUnpackedDimensions: 1),
      dimensions: [6],
      numUnpackedDimensions: 1,
    );
    final dst = LogicArray([6], 1, name: 'dst', numUnpackedDimensions: 1);

    for (var index = 2; index <= 4; index++) {
      dst.elements[index] <= src.elements[index];
    }

    addOutput('y', width: 6) <= dst.leafElements.rswizzle();
  }
}

/// Partially assigns multi-bit array elements, which must not be collapsed by
/// the one-bit range assignment optimization.
class PartialWideArrayRangeAssignment extends Module {
  PartialWideArrayRangeAssignment()
      : super(name: 'partial_wide_array_range_assignment') {
    final src = addInputArray(
      'src',
      LogicArray([4], 2),
      dimensions: [4],
      elementWidth: 2,
    );
    final dst = LogicArray([4], 2, name: 'dst');

    for (var index = 1; index <= 2; index++) {
      dst.elements[index] <= src.elements[index];
    }

    addOutput('y', width: 8) <= dst.leafElements.rswizzle();
  }
}

/// Partially connects net array elements; range collapse must leave these for
/// the net connection flow instead of emitting procedural assignments.
class PartialNetArrayRangeAssignment extends Module {
  PartialNetArrayRangeAssignment()
      : super(name: 'partial_net_array_range_assignment') {
    final src = addInOutArray(
      'src',
      LogicArray.net([6], 1),
      dimensions: [6],
    );
    final mirror = addInOut('mirror', LogicNet(width: 6), width: 6);
    final dst = LogicArray.net([6], 1, name: 'dst');

    for (var index = 2; index <= 4; index++) {
      dst.elements[index] <= src.elements[index];
    }

    mirror <= dst.leafElements.rswizzle();
  }
}

/// Partially connects a flat net bus through bit selections; this is outside
/// array range collapse and should stay in the net connection flow.
class PartialLogicNetRangeAssignment extends Module {
  PartialLogicNetRangeAssignment()
      : super(name: 'partial_logic_net_range_assignment') {
    final src = addInOut('src', LogicNet(width: 6), width: 6);
    final mirror = addInOut('mirror', LogicNet(width: 6), width: 6);
    final dst = LogicNet(width: 6, name: 'dst');

    for (var index = 2; index <= 4; index++) {
      dst.slice(index, index) <= src.slice(index, index);
    }

    mirror <= dst;
  }
}

/// Inverts a bus of the given `width`.
class InverterMod extends Module {
  Logic get o => output('o');
  InverterMod(Logic i, {int width = 1}) {
    i = addInput('i', i, width: width);
    addOutput('o', width: width) <= ~i;
  }
}

/// Bidirectionally connects two nets of the given `width`.
class NetPassthrough extends Module {
  NetPassthrough(Logic x, Logic y, {int width = 1}) {
    x = addInOut('x', x, width: width);
    y = addInOut('y', y, width: width);
    x <= y;
  }
}

/// A flat input bus blasted into an array of `dimensions`/`elementWidth`, each
/// leaf element feeding an [InverterMod] (computing `~a`).  The intermediate
/// array should disappear and the submodule ports should reference the input
/// bits directly.  When `reversed`, leaves are consumed in reverse order.
class ArrayElementFanout extends Module {
  ArrayElementFanout(
    Logic a, {
    List<int> dimensions = const [4],
    int elementWidth = 1,
    bool reversed = false,
  }) {
    final total = dimensions.reduce((x, y) => x * y) * elementWidth;
    a = addInput('a', a, width: total);
    final arr = LogicArray(dimensions, elementWidth,
        name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final leaves = arr.leafElements;
    final results = <Logic>[];
    for (var i = 0; i < leaves.length; i++) {
      final srcIdx = reversed ? leaves.length - 1 - i : i;
      results.add(InverterMod(leaves[srcIdx], width: elementWidth).o);
    }

    addOutput('y', width: total) <= results.rswizzle();
  }
}

/// Net version of [ArrayElementFanout]: a flat inout bus blasted into a net
/// array whose leaves bidirectionally connect (via [NetPassthrough]) to an
/// output bus.  The intermediate array and its `net_connect`s should disappear.
class NetArrayElementFanout extends Module {
  NetArrayElementFanout(
    LogicNet a,
    LogicNet b, {
    List<int> dimensions = const [4],
    int elementWidth = 1,
  }) {
    final total = dimensions.reduce((x, y) => x * y) * elementWidth;
    a = addInOut('a', a, width: total);
    b = addInOut('b', b, width: total);
    final arr = LogicArray.net(dimensions, elementWidth,
        name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final leaves = arr.leafElements;
    for (var i = 0; i < leaves.length; i++) {
      NetPassthrough(
          leaves[i], b.getRange(i * elementWidth, (i + 1) * elementWidth),
          width: elementWidth);
    }
  }
}

/// An array where only some leaf elements are driven (the first and last are
/// left undriven), with the whole array reconstructed via a swizzle.  This must
/// NOT be inlined away (partial inlining would change `x`/`z` behavior of the
/// undriven bits).
class PartiallyDrivenArray extends Module {
  PartiallyDrivenArray(Logic a, {List<int> dimensions = const [4]}) {
    final total = dimensions.reduce((x, y) => x * y);
    a = addInput('a', a, width: total - 2);
    final arr =
        LogicArray(dimensions, 1, name: 'arr', naming: Naming.mergeable);

    final leaves = arr.leafElements;
    // drive everything except the first and last leaf
    for (var i = 1; i < leaves.length - 1; i++) {
      leaves[i] <= a[i - 1];
    }

    addOutput('y', width: total) <= leaves.rswizzle();
  }
}

/// The array's leaves feed submodules, but the whole array is ALSO consumed as
/// an aggregate (assigned to an output array).  Because of the aggregate use,
/// the elements must NOT be inlined and the array must remain declared.
class ArrayElementsWithAggregateUse extends Module {
  ArrayElementsWithAggregateUse(Logic a) {
    a = addInput('a', a, width: 4);
    final arr = LogicArray([4], 1, name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final results = <Logic>[];
    for (final leaf in arr.leafElements) {
      results.add(InverterMod(leaf).o);
    }
    addOutput('y', width: 4) <= results.rswizzle();

    // whole-array (aggregate) use, which blocks element inlining
    addOutputArray('arrCopy', dimensions: [4]) <= arr;
  }
}

/// An array provided as an input *port* whose leaves feed submodules.  Port
/// array elements are not clearable, so the port must remain; generation must
/// still be correct.
class ArrayPortElementsToSubmodules extends Module {
  ArrayPortElementsToSubmodules(LogicArray a) {
    a = addInputArray('a', a,
        dimensions: a.dimensions, elementWidth: a.elementWidth);
    final results = <Logic>[];
    for (final leaf in a.leafElements) {
      results.add(InverterMod(leaf, width: a.elementWidth).o);
    }
    addOutput('y', width: a.width) <= results.rswizzle();
  }
}

/// A struct with a [LogicArray] field, provided as a port, whose array leaves
/// feed submodules.  Struct-port array elements must NOT be inlined.
class StructWithArrayField extends LogicStructure {
  final LogicArray arr;
  final Logic flag;

  factory StructWithArrayField({String name = 'swaf'}) =>
      StructWithArrayField._(
        LogicArray([4], 1, name: 'arr'),
        Logic(name: 'flag'),
        name: name,
      );

  StructWithArrayField._(this.arr, this.flag, {super.name})
      : super([arr, flag]);

  @override
  StructWithArrayField clone({String? name}) =>
      StructWithArrayField(name: name ?? this.name);
}

/// Feeds the leaves of a struct-port array field into submodules.
class StructArrayFieldToSubmodules extends Module {
  StructArrayFieldToSubmodules(StructWithArrayField s) {
    s = StructWithArrayField()..gets(addInput('s', s, width: s.width));
    final results = <Logic>[];
    for (final leaf in s.arr.leafElements) {
      results.add(InverterMod(leaf).o);
    }
    addOutput('y', width: s.arr.width) <= results.rswizzle();
  }
}

class ArrayModuleWithNetIntermediates extends Module {
  ArrayModuleWithNetIntermediates(LogicArray a, LogicArray b) {
    a = addInOutArray('a', a,
        dimensions: a.dimensions,
        elementWidth: a.elementWidth,
        numUnpackedDimensions: a.numUnpackedDimensions);

    final intermediate = LogicArray.net(
      a.dimensions,
      a.elementWidth,
      name: 'intermediate',
      naming: Naming.reserved,
    );

    b = addInOutArray('b', b,
        dimensions: a.dimensions,
        elementWidth: a.elementWidth,
        numUnpackedDimensions: a.numUnpackedDimensions);

    intermediate <= a;
    b <= intermediate;
  }
}

/// Child with a single array input port whose whole value is inverted to `y`.
class ArrayPortInvChild extends Module {
  Logic get y => output('y');
  ArrayPortInvChild(LogicArray a, {int n = 4, int elementWidth = 1})
      : super(name: 'arr_inv_child') {
    a = addInputArray('a', a, dimensions: [n], elementWidth: elementWidth);
    addOutput('y', width: n * elementWidth) <= ~a.elements.rswizzle();
  }
}

/// Parent feeding `n` individual signals (each `elementWidth` wide) into a
/// single child array port, element-by-element through a mergeable intermediate
/// array.  `perm` optionally reorders which signal drives which element.
///
/// The intermediate array (and all of its per-element assignments) should be
/// collapsed into a single inline concatenation on the child port.
class IndividualSignalsToArrayPort extends Module {
  Logic get y => output('y');
  IndividualSignalsToArrayPort(List<Logic> sigs,
      {int elementWidth = 1, List<int>? perm}) {
    final n = sigs.length;
    final ins = [
      for (var i = 0; i < n; i++)
        addInput('sig$i', sigs[i], width: elementWidth)
    ];
    final arr =
        LogicArray([n], elementWidth, name: 'arr', naming: Naming.mergeable);
    final child = ArrayPortInvChild(arr, n: n, elementWidth: elementWidth);
    for (var i = 0; i < n; i++) {
      arr.elements[i] <= ins[perm == null ? i : perm[i]];
    }
    addOutput('y', width: n * elementWidth) <= child.y;
  }
}

/// Like [IndividualSignalsToArrayPort], but each array element is connected
/// through a mergeable intermediate before aggregate connection inlining runs.
class MergedSourcesToArrayPort extends Module {
  Logic get y => output('y');
  MergedSourcesToArrayPort(List<Logic> sigs, {int elementWidth = 1}) {
    final n = sigs.length;
    final ins = [
      for (var i = 0; i < n; i++)
        addInput('sig$i', sigs[i], width: elementWidth)
    ];
    final arr =
        LogicArray([n], elementWidth, name: 'arr', naming: Naming.mergeable);
    final child = ArrayPortInvChild(arr, n: n, elementWidth: elementWidth);
    for (var i = 0; i < n; i++) {
      final intermediate = Logic(
        width: elementWidth,
        name: 'intermediate$i',
        naming: Naming.mergeable,
      );
      arr.elements[i] <= intermediate;
      intermediate <= ins[i];
    }
    addOutput('y', width: n * elementWidth) <= child.y;
  }
}

/// Parent feeding ranged slices from one source bus into a single child array
/// port through a mergeable intermediate array.
class RangeSourcesToArrayPort extends Module {
  Logic get y => output('y');
  RangeSourcesToArrayPort() {
    const n = 4;
    const elementWidth = 16;
    final src = addInput('src', Logic(width: n * elementWidth),
        width: n * elementWidth);
    final srcSlice = Logic(
      width: n * elementWidth,
      name: 'srcSlice',
      naming: Naming.mergeable,
    );
    final arr =
        LogicArray([n], elementWidth, name: 'arr', naming: Naming.mergeable);
    final child = ArrayPortInvChild(arr, elementWidth: elementWidth);

    srcSlice <= src;
    for (var i = 0; i < n; i++) {
      arr.elements[i] <=
          srcSlice.getRange(i * elementWidth, (i + 1) * elementWidth);
    }

    addOutput('y', width: n * elementWidth) <= child.y;
  }
}

/// Child with a single inout net array port bidirectionally mirrored to `b`.
class ArrayPortNetChild extends Module {
  ArrayPortNetChild(LogicArray a, LogicNet b, {int n = 4})
      : super(name: 'arr_net_child') {
    a = addInOutArray('a', a, dimensions: [n]);
    b = addInOut('b', b, width: n);
    b <= a.elements.rswizzle();
  }
}

/// Net version of [IndividualSignalsToArrayPort]: `n` individual inout nets are
/// connected element-by-element to a single child inout array port through a
/// mergeable intermediate net array.  The intermediate array and its
/// `net_connect`s should be collapsed into a single inline concatenation.
class IndividualNetsToArrayPort extends Module {
  IndividualNetsToArrayPort(List<LogicNet> sigs, LogicNet out,
      {List<int>? perm}) {
    final n = sigs.length;
    final ins = [for (var i = 0; i < n; i++) addInOut('sig$i', sigs[i])];
    final o = addInOut('out', out, width: n);
    final arr = LogicArray.net([n], 1, name: 'arr', naming: Naming.mergeable);
    ArrayPortNetChild(arr, o, n: n);
    for (var i = 0; i < n; i++) {
      arr.elements[i] <= ins[perm == null ? i : perm[i]];
    }
  }
}

/// Builds a mergeable array from individual signals and uses it as a whole
/// twice (two child array ports), so the single-aggregate-use restriction
/// prevents collapsing and the array stays declared.
class MultiUseAggregate extends Module {
  Logic get y => output('y');
  Logic get z => output('z');
  MultiUseAggregate(List<Logic> sigs) {
    final n = sigs.length;
    final ins = [for (var i = 0; i < n; i++) addInput('sig$i', sigs[i])];
    final arr = LogicArray([n], 1, name: 'arr', naming: Naming.mergeable);
    for (var i = 0; i < n; i++) {
      arr.elements[i] <= ins[i];
    }
    addOutput('y', width: n) <= ArrayPortInvChild(arr, n: n).y;
    addOutput('z', width: n) <= ArrayPortInvChild(arr, n: n).y;
  }
}

/// Child with a single array output port whose whole value is the inverted
/// input bus (`a = ~x`).
class ArrayOutChild extends Module {
  LogicArray get a => output('a') as LogicArray;
  ArrayOutChild(Logic x, {int n = 4}) : super(name: 'array_out_child') {
    x = addInput('x', x, width: n);
    addOutputArray('a', dimensions: [n]) <= (~x).elements.rswizzle();
  }
}

/// The opposite shape of the originally-reported issue (logic direction): a
/// submodule's array *output* port whose individual elements each drive a
/// separate single (scalar) output wire.  This must generate correct
/// SystemVerilog.
class ArrayPortToIndividualSignals extends Module {
  ArrayPortToIndividualSignals(Logic x, {int n = 4}) {
    x = addInput('x', x, width: n);
    final child = ArrayOutChild(x, n: n);
    for (var i = 0; i < n; i++) {
      addOutput('y$i') <= child.a.elements[i];
    }
  }
}

/// The opposite shape of the originally-reported issue (net direction): a
/// submodule's inout array port whose individual elements each connect to a
/// separate single (scalar) net.  The intermediate array and its
/// `net_connect`s should collapse into a single inline concatenation.
class ArrayPortToIndividualNets extends Module {
  ArrayPortToIndividualNets(List<LogicNet> sigs, LogicNet b) {
    final n = sigs.length;
    final outs = [for (var i = 0; i < n; i++) addInOut('y$i', sigs[i])];
    b = addInOut('b', b, width: n);
    final arr = LogicArray.net([n], 1, name: 'arr', naming: Naming.mergeable);
    ArrayPortNetChild(arr, b, n: n);
    for (var i = 0; i < n; i++) {
      outs[i] <= arr.elements[i];
    }
  }
}

/// An intermediate mergeable array whose elements are all driven by elements of
/// one common parent array (here, reversed), then passed to a child array port.
/// The common-parent guard must leave this to the other collapsing mechanisms
/// rather than fabricating a redundant concatenation.
class RearrangeOneArray extends Module {
  Logic get y => output('y');
  RearrangeOneArray(LogicArray src, {int n = 4}) {
    src = addInputArray('src', src, dimensions: [n]);
    final arr = LogicArray([n], 1, name: 'arr', naming: Naming.mergeable);
    final child = ArrayPortInvChild(arr, n: n);
    for (var i = 0; i < n; i++) {
      arr.elements[i] <= src.elements[n - 1 - i];
    }
    addOutput('y', width: n) <= child.y;
  }
}

/// A child whose array input port `a` is declared *expressionless*, so the
/// aggregate connection inlining must NOT inline a concatenation into it; the
/// intermediate array and its per-element assignments must remain.
class ExpressionlessArrayPortChild extends Module with SystemVerilog {
  Logic get y => output('y');
  ExpressionlessArrayPortChild(LogicArray a, {int n = 4})
      : super(name: 'expressionless_child') {
    a = addInputArray('a', a, dimensions: [n]);
    addOutput('y', width: n) <= a.elements.rswizzle();
  }

  @override
  List<String> get expressionlessInputs => const ['a'];

  @override
  String? definitionVerilog(String definitionType) => null;
}

/// Feeds individual signals through a mergeable array into the expressionless
/// array port of [ExpressionlessArrayPortChild].
class IndividualSignalsToExpressionlessPort extends Module {
  Logic get y => output('y');
  IndividualSignalsToExpressionlessPort(List<Logic> sigs) {
    final n = sigs.length;
    final ins = [for (var i = 0; i < n; i++) addInput('sig$i', sigs[i])];
    final arr = LogicArray([n], 1, name: 'arr', naming: Naming.mergeable);
    final child = ExpressionlessArrayPortChild(arr, n: n);
    for (var i = 0; i < n; i++) {
      arr.elements[i] <= ins[i];
    }
    addOutput('y', width: n) <= child.y;
  }
}

/// A child whose single inout net array port `data` is bidirectionally mirrored
/// to `mirror` (`mirror = data.rswizzle()`).
class WholeNetBusChild extends Module {
  WholeNetBusChild(LogicNet data, LogicNet mirror, {int n = 8})
      : super(name: 'whole_net_bus_child') {
    data = addInOut('data', data, width: n);
    mirror = addInOut('mirror', mirror, width: n);
    mirror <= data;
  }
}

/// Case A (flat whole-bus): a flat net bus `bus` whose every bit is tied
/// bit-by-bit to an individual net, and which is then passed *as a whole* to a
/// child inout port.  The bus and all of its per-bit `net_connect`s should
/// collapse into a single inline concatenation of those nets on the child port.
///
/// `busNaming` controls whether the intermediate bus is collapsible.
class WholeNetBusToPort extends Module {
  WholeNetBusToPort(List<LogicNet> nets, LogicNet mirror,
      {Naming busNaming = Naming.mergeable})
      : super(name: 'whole_net_bus_to_port') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: busNaming);
    for (var i = 0; i < n; i++) {
      bus.slice(i, i) <= netPorts[i];
    }
    WholeNetBusChild(bus, mirror, n: n);
  }
}

/// Like [WholeNetBusToPort], but one bus slice also feeds an inline gate
/// expression.  Collapsing the whole bus must not leave that expression reading
/// an undriven subset helper.
class WholeNetBusToPortWithInlineSubsetConsumer extends Module {
  WholeNetBusToPortWithInlineSubsetConsumer(
      List<LogicNet> nets, LogicNet mirror)
      : super(name: 'whole_net_bus_to_port_with_inline_subset_consumer') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    final enable = addInput('enable', Logic());
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus');
    for (var i = 0; i < n; i++) {
      bus.slice(i, i) <= netPorts[i];
    }

    addOutput('z') <= enable & ~bus.slice(0, 0);
    WholeNetBusChild(bus, mirror, n: n);
  }
}

/// Reads every bit of a net bus through subset helpers, while the whole bus is
/// also consumed by a child.  These read-only helpers must not be mistaken for
/// bit definers and removed out from under the inline expression.
class WholeNetBusToPortWithReadOnlyInlineSubsetConsumer extends Module {
  WholeNetBusToPortWithReadOnlyInlineSubsetConsumer(LogicNet mirror,
      {int n = 4})
      : super(
            name:
                'whole_net_bus_to_port_with_read_only_inline_subset_consumer') {
    final enable = addInput('enable', Logic());
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus');
    final guarded = <Logic>[];

    for (var i = 0; i < n; i++) {
      final selected = bus.slice(i, i);
      guarded.add(enable & ~selected);
    }

    addOutput('z', width: n) <= guarded.rswizzle();
    WholeNetBusChild(bus, mirror, n: n);
  }
}

/// Reproduces the current naming-order issue where temporary [BusSubset]
/// instances that will be collapsed still claim basenames before surviving
/// signals can use them.
class WholeNetBusCollapseNamingCollision extends Module {
  WholeNetBusCollapseNamingCollision()
      : super(name: 'whole_net_bus_collapse_naming_collision') {
    final netPorts = [
      for (var i = 0; i < 2; i++) addInOut('net$i', LogicNet()),
    ];
    final mirror = addInOut('mirror', LogicNet(width: 2), width: 2);
    final bus = LogicNet(width: 2, name: 'bus');
    for (var i = 0; i < 2; i++) {
      bus.slice(i, i) <= netPorts[i];
    }
    WholeNetBusChild(bus, mirror, n: 2);

    final sig = addInput('sig', Logic());
    final busNamedSignal = Logic(name: 'bussubset');
    busNamedSignal <= sig;
    addOutput('busSubsetOut') <= busNamedSignal;
  }
}

/// A child whose inout net *array* port `data` is bidirectionally mirrored to
/// `mirror` (`mirror = data.elements.rswizzle()`).
class ArrayNetBusChild extends Module {
  ArrayNetBusChild(LogicNet bus, LogicNet mirror, {int n = 8})
      : super(name: 'array_net_bus_child') {
    final data = addInOutArray('data', bus, dimensions: [n]);
    mirror = addInOut('mirror', mirror, width: n);
    mirror <= data.elements.rswizzle();
  }
}

/// Case B (bit-wise pass-through into array port): a flat net bus `bus` whose
/// every bit is tied to an individual net, then passed to a child inout *array*
/// port.  Because the bus bit-selects feed the array elements through
/// pass-through `BusSubset`s, the bus and all of its `net_connect`s should be
/// traced away and collapsed into a single inline concatenation of those nets
/// on the child port.
class BitwiseNetBusToArrayPort extends Module {
  BitwiseNetBusToArrayPort(List<LogicNet> nets, LogicNet mirror,
      {Naming busNaming = Naming.mergeable})
      : super(name: 'bitwise_net_bus_to_array_port') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: busNaming);
    for (var i = 0; i < n; i++) {
      bus.slice(i, i) <= netPorts[i];
    }
    ArrayNetBusChild(bus, mirror, n: n);
  }
}

/// Like [BitwiseNetBusToArrayPort], but the same subset helper that ties one
/// net into the bus also feeds an inline gate expression.
class BitwiseNetBusToArrayPortWithInlineSubsetConsumer extends Module {
  BitwiseNetBusToArrayPortWithInlineSubsetConsumer(
      List<LogicNet> nets, LogicNet mirror)
      : super(
            name: 'bitwise_net_bus_to_array_port_with_inline_subset_consumer') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    final enable = addInput('enable', Logic());
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus');
    for (var i = 0; i < n; i++) {
      final selected = bus.slice(i, i);
      selected <= netPorts[i];
      if (i == 0) {
        addOutput('z') <= enable & ~selected;
      }
    }
    ArrayNetBusChild(bus, mirror, n: n);
  }
}

/// A flat net bus passed as a whole to a child port, but also read by a second
/// consumer (another child).  The extra whole use must prevent the bus from
/// collapsing.
class WholeNetBusMultiUse extends Module {
  WholeNetBusMultiUse(List<LogicNet> nets, LogicNet mirror1, LogicNet mirror2)
      : super(name: 'whole_net_bus_multi_use') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror1 = addInOut('mirror1', mirror1, width: n);
    mirror2 = addInOut('mirror2', mirror2, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: Naming.mergeable);
    for (var i = 0; i < n; i++) {
      bus.slice(i, i) <= netPorts[i];
    }
    WholeNetBusChild(bus, mirror1, n: n);
    WholeNetBusChild(bus, mirror2, n: n);
  }
}

/// A flat net bus whose lower bits are tied to individual nets, but whose
/// top bit is tied to *another bit of itself* (`bus[n-1] <= bus[0]`).  That
/// self-connection puts a second `BusSubset` definer on bit 0, so the bus must
/// *not* be collapsed (the "each bit driven exactly once" guard must reject
/// it).  Sends the bus either as a whole (`toArray` false) or into an array
/// port (`toArray` true).
class SelfBitNetBus extends Module {
  SelfBitNetBus(List<LogicNet> nets, LogicNet mirror, {bool toArray = false})
      : super(name: 'self_bit_net_bus') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: Naming.mergeable);
    for (var i = 0; i < n - 1; i++) {
      bus.slice(i, i) <= netPorts[i];
    }
    // top bit follows bit 0 of the same bus
    bus.slice(n - 1, n - 1) <= bus.slice(0, 0);
    if (toArray) {
      ArrayNetBusChild(bus, mirror, n: n);
    } else {
      WholeNetBusChild(bus, mirror, n: n);
    }
  }
}

/// A pure self-loop net bus: `bus[1] <= bus[0]` with no other drivers, passed
/// as a whole to a child port.  Both bits merge into a single standalone net,
/// so the bus may safely collapse into `{M, M}` where `M` is that merged net
/// (it is *not* a slice of the deleted bus, so there is no dangling
/// self-reference).
class PureSelfLoopNetBus extends Module {
  PureSelfLoopNetBus(LogicNet mirror, {bool toArray = false})
      : super(name: 'pure_self_loop_net_bus') {
    mirror = addInOut('mirror', mirror, width: 2);
    final bus = LogicNet(width: 2, name: 'bus', naming: Naming.mergeable);
    bus.slice(1, 1) <= bus.slice(0, 0);
    if (toArray) {
      ArrayNetBusChild(bus, mirror, n: 2);
    } else {
      WholeNetBusChild(bus, mirror, n: 2);
    }
  }
}

/// Models the `connectPorts(top.bit_i, child.netPort[i])` receiver scenario:
/// each external bit net is tied into one bit of a child's whole net bus via
/// [Logic.assignSubset].  `assignSubset` introduces an intermediate `*_subset`
/// net array whose elements are pure pass-throughs; those elements must be
/// forwarded directly into the child connection so that no per-bit
/// `net_connect` remains.
class AssignSubsetReceiver extends Module {
  AssignSubsetReceiver(List<LogicNet> nets, LogicNet mirror,
      {Naming busNaming = Naming.mergeable})
      : super(name: 'assign_subset_receiver') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: busNaming);
    WholeNetBusChild(bus, mirror, n: n);
    for (var i = 0; i < n; i++) {
      bus.assignSubset([netPorts[i]], start: i);
    }
  }
}

/// Like [AssignSubsetReceiver] but assigns the external bits in non-monotonic
/// order, exercising that the forwarding preserves per-bit positions.
class AssignSubsetReceiverScrambled extends Module {
  AssignSubsetReceiverScrambled(List<LogicNet> nets, LogicNet mirror)
      : super(name: 'assign_subset_receiver_scrambled') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: Naming.mergeable);
    WholeNetBusChild(bus, mirror, n: n);
    // assign in a scrambled order; each still targets its own bit
    for (final i in [3, 0, 2, 1].where((i) => i < n)) {
      bus.assignSubset([netPorts[i]], start: i);
    }
    // cover any remaining bits in order (for n != 4)
    for (var i = 4; i < n; i++) {
      bus.assignSubset([netPorts[i]], start: i);
    }
  }
}

/// The driver-direction counterpart of [AssignSubsetReceiver]: each external
/// bit net *receives* a one-bit slice of a child's whole net bus via
/// `assignSubset`.  The per-bit `*_subset` pass-throughs must still be
/// forwarded away so the whole connection collapses with no per-bit
/// `net_connect`.
class AssignSubsetDriver extends Module {
  AssignSubsetDriver(List<LogicNet> nets, LogicNet mirror,
      {Naming busNaming = Naming.mergeable})
      : super(name: 'assign_subset_driver') {
    final n = nets.length;
    final netPorts = [
      for (var i = 0; i < n; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: busNaming);
    WholeNetBusChild(bus, mirror, n: n);
    for (var i = 0; i < n; i++) {
      netPorts[i].assignSubset([bus.slice(i, i)]);
    }
  }
}

/// A non-net child mirroring a whole input bus `data` to output `mirror`.
class WholeBusChild extends Module {
  WholeBusChild(Logic data, {int n = 4}) : super(name: 'whole_bus_child') {
    data = addInput('data', data, width: n);
    addOutput('mirror', width: n) <= data;
  }
}

/// A non-net child mirroring an input *array* bus `data` to output `mirror`.
class ArrayBusChild extends Module {
  ArrayBusChild(Logic data, {int n = 4}) : super(name: 'array_bus_child') {
    final d = addInputArray('data', data, dimensions: [n]);
    addOutput('mirror', width: n) <= d.elements.rswizzle();
  }
}

/// How individual bits are tied into the intermediate bus in the kitchen-sink
/// collapse modules.
enum TieMechanism {
  /// `bus.slice(i, i) <= bit[i]` (nets only — non-net slices are read-only).
  directSlice,

  /// `bus.assignSubset([bit[i]], start: i)` (the receiver direction).
  subsetReceiver,

  /// `bit[i].assignSubset([bus.slice(i, i)])` (the driver direction; nets
  /// only).
  subsetDriver,
}

/// A configuration of independent toggles describing one collapse scenario, so
/// a single parameterized module can exercise every combination of them.
class CollapseConfig {
  /// Whether the signals/bus are nets (`LogicNet`) or plain `Logic`.
  final bool isNet;

  /// How the individual bits are tied into the bus.
  final TieMechanism mechanism;

  /// Whether the bus is consumed via a child *array* port (vs a whole port).
  final bool toArray;

  /// Whether the bits are tied in a non-monotonic order.
  final bool scrambled;

  /// Whether the bus may collapse (`Naming.mergeable`) or must be preserved
  /// (`Naming.renameable`).
  final bool collapsibleBus;

  /// Whether only the low half of the bus is driven (undriven bits stay `z`).
  final bool partial;

  /// Whether a second consumer reads the whole bus (which blocks collapse).
  final bool multiUse;

  const CollapseConfig({
    required this.isNet,
    required this.mechanism,
    required this.toArray,
    required this.scrambled,
    required this.collapsibleBus,
    required this.partial,
    required this.multiUse,
  });

  /// The bus width used by the kitchen-sink modules.
  static const width = 4;

  /// The number of bits actually tied into the bus (half when [partial]).
  int get driven => partial ? width ~/ 2 : width;

  /// The intermediate bus and any `*_subset` arrays should fully dissolve into
  /// a single inline concatenation only when the bus is collapsible, drives a
  /// *whole* (non-array) child port, and there is no partial drive or extra
  /// use.  Array ports are bit-blasted into per-element connections, so the
  /// bus survives as a named intermediate there.
  bool get fullyCollapses =>
      collapsibleBus && !partial && !multiUse && !toArray;

  /// The `*_subset` pass-through arrays should be forwarded away whenever the
  /// whole connection can collapse (independent of bus naming).
  bool get noSubset => !partial && !multiUse;

  String get description => [
        if (isNet) 'net' else 'logic',
        mechanism.name,
        if (toArray) 'arrayPort' else 'wholePort',
        if (scrambled) 'scrambled' else 'inOrder',
        if (collapsibleBus) 'mergeableBus' else 'renameableBus',
        if (partial) 'partial' else 'full',
        if (multiUse) 'multiUse' else 'singleUse',
      ].join('/');
}

/// A deterministic order (possibly non-monotonic) in which to tie the [k] bits.
List<int> _tieOrder(int k, {required bool scrambled}) {
  if (!scrambled) {
    return [for (var i = 0; i < k; i++) i];
  }
  return [
    ...[3, 0, 2, 1].where((i) => i < k),
    for (var i = 4; i < k; i++) i,
  ];
}

/// The net (`LogicNet`) kitchen-sink: ties `k` external nets into an
/// intermediate bus via [CollapseConfig.mechanism], then mirrors the bus to
/// one (or two, when [CollapseConfig.multiUse]) child(ren).  Because nets are
/// bidirectional, driving the external nets propagates through to every mirror
/// regardless of which `assignSubset` direction is used.
class NetKitchenSink extends Module {
  final CollapseConfig config;
  NetKitchenSink(this.config, List<LogicNet> nets, LogicNet mirror1,
      [LogicNet? mirror2])
      : super(name: 'net_kitchen_sink') {
    const n = CollapseConfig.width;
    final k = config.driven;
    final netPorts = [
      for (var i = 0; i < k; i++) addInOut('net$i', nets[i]),
    ];
    final bus = LogicNet(
      width: n,
      name: 'bus',
      naming: config.collapsibleBus ? Naming.mergeable : Naming.renameable,
    );
    for (final i in _tieOrder(k, scrambled: config.scrambled)) {
      switch (config.mechanism) {
        case TieMechanism.directSlice:
          bus.slice(i, i) <= netPorts[i];
        case TieMechanism.subsetReceiver:
          bus.assignSubset([netPorts[i]], start: i);
        case TieMechanism.subsetDriver:
          netPorts[i].assignSubset([bus.slice(i, i)]);
      }
    }
    _consume(bus, addInOut('mirror1', mirror1, width: n), n);
    if (config.multiUse) {
      _consume(bus, addInOut('mirror2', mirror2!, width: n), n);
    }
  }

  void _consume(LogicNet bus, LogicNet mirror, int n) {
    if (config.toArray) {
      ArrayNetBusChild(bus, mirror, n: n);
    } else {
      WholeNetBusChild(bus, mirror, n: n);
    }
  }
}

/// The non-net (`Logic`) kitchen-sink: ties external input bits into an
/// intermediate bus via `assignSubset` (the only valid non-net mechanism),
/// then mirrors the bus to one (or two, when [CollapseConfig.multiUse])
/// child(ren) whose outputs are surfaced on `y` (and `y2`).
class LogicKitchenSink extends Module {
  final CollapseConfig config;
  LogicKitchenSink(this.config, List<Logic> bits)
      : super(name: 'logic_kitchen_sink') {
    const n = CollapseConfig.width;
    final ins = [for (var i = 0; i < n; i++) addInput('b$i', bits[i])];
    final bus = Logic(
      width: n,
      name: 'bus',
      naming: config.collapsibleBus ? Naming.mergeable : Naming.renameable,
    );
    for (final i in _tieOrder(n, scrambled: config.scrambled)) {
      bus.assignSubset([ins[i]], start: i);
    }
    addOutput('y', width: n) <= _consume(bus, n);
    if (config.multiUse) {
      addOutput('y2', width: n) <= _consume(bus, n);
    }
  }

  Logic _consume(Logic bus, int n) => config.toArray
      ? (ArrayBusChild(bus, n: n).output('mirror'))
      : (WholeBusChild(bus, n: n).output('mirror'));
}

/// A non-net child whose input `i` is inverted onto output `o`.
class LogicInvChild extends Module {
  LogicInvChild(Logic i, {int n = 4}) : super(name: 'logic_inv_child') {
    i = addInput('i', i, width: n);
    addOutput('o', width: n) <= ~i;
  }
}

/// A child whose input source can be driven after construction.
class LateSubsetInputChild extends Module {
  LateSubsetInputChild({super.name = 'late_subset_input_child'}) {
    addInput('data', Logic(width: 8), width: 8);
    addOutput('out') <= input('data')[0];
  }
}

/// Drives a child input source late using [Logic.assignSubset].
class LateSubsetInputTop extends Module {
  LateSubsetInputTop() : super(name: 'late_subset_input_top') {
    final source = addInput('source', Logic(width: 8), width: 8);
    final child = LateSubsetInputChild();

    child.inputSource('data').assignSubset(source.elements);

    addOutput('y') <= child.output('out');
  }
}

/// Drives a child input source late from a slice of a wider source.
class LateSlicedSubsetInputTop extends Module {
  LateSlicedSubsetInputTop() : super(name: 'late_sliced_subset_input_top') {
    final source = addInput('source', Logic(width: 16), width: 16);
    final child = LateSubsetInputChild();

    child.inputSource('data').assignSubset([
      for (var index = 0; index < 8; index++) source[index + 4],
    ]);

    addOutput('y') <= child.output('out');
  }
}

/// A child that forwards its input to an output for sibling connection tests.
class SiblingSubsetProducer extends Module {
  SiblingSubsetProducer({super.name = 'sibling_subset_producer'}) {
    final seed = addInput('seed', Logic(width: 4), width: 4);
    addOutput('result', width: 4) <= seed;
  }
}

/// A child that observes a bit inside a late-driven input source.
class SiblingSubsetConsumer extends Module {
  SiblingSubsetConsumer({super.name = 'sibling_subset_consumer'}) {
    addInput('data', Logic(width: 8), width: 8);
    addOutput('observed') <= input('data')[2];
  }
}

/// Width-matched sibling consumer for full-width subset mapping tests.
class SiblingFullSubsetConsumer extends Module {
  SiblingFullSubsetConsumer({super.name = 'sibling_full_subset_consumer'}) {
    addInput('data', Logic(width: 4), width: 4);
    addOutput('observed') <= input('data')[0];
  }
}

/// Drives one sibling's input source from another sibling's output subset.
class SiblingOutputToInputSubsetTop extends Module {
  SiblingOutputToInputSubsetTop()
      : super(name: 'sibling_output_to_input_subset_top') {
    final source = addInput('source', Logic(width: 4), width: 4);
    final producer = SiblingSubsetProducer();
    producer.inputSource('seed') <= source;

    final consumer = SiblingSubsetConsumer();
    consumer.inputSource('data').assignSubset(
          producer.output('result').elements,
          start: 2,
        );

    addOutput('y') <= consumer.output('observed');
  }
}

/// Drives one sibling's full input source from another sibling's full output.
class SiblingFullOutputToInputSubsetTop extends Module {
  SiblingFullOutputToInputSubsetTop()
      : super(name: 'sibling_full_output_to_input_subset_top') {
    final source = addInput('source', Logic(width: 4), width: 4);
    final producer = SiblingSubsetProducer();
    producer.inputSource('seed') <= source;

    final consumer = SiblingFullSubsetConsumer();
    consumer.inputSource('data').assignSubset(
          producer.output('result').elements,
        );

    addOutput('y') <= consumer.output('observed');
  }
}

/// Array-output sibling variant of [SiblingSubsetProducer].
class SiblingArraySubsetProducer extends Module {
  SiblingArraySubsetProducer({super.name = 'sibling_array_subset_producer'}) {
    final seed = addInput('seed', Logic(width: 4), width: 4);
    final result = addOutputArray('result', dimensions: [4]);

    for (var index = 0; index < 4; index++) {
      result.elements[index] <= seed[index];
    }
  }
}

/// Array-input sibling variant of [SiblingSubsetConsumer].
class SiblingArraySubsetConsumer extends Module {
  SiblingArraySubsetConsumer({super.name = 'sibling_array_subset_consumer'}) {
    final data = addInputArray('data', LogicArray([8], 1), dimensions: [8]);
    addOutput('observed') <= data.elements[2];
  }
}

/// Drives one sibling's input array source from another sibling's output array.
class SiblingArrayOutputToInputSubsetTop extends Module {
  SiblingArrayOutputToInputSubsetTop()
      : super(name: 'sibling_array_output_to_input_subset_top') {
    final source = addInput('source', Logic(width: 4), width: 4);
    final producer = SiblingArraySubsetProducer();
    producer.inputSource('seed') <= source;

    final consumer = SiblingArraySubsetConsumer();
    (consumer.inputSource('data') as LogicArray).assignSubset(
      (producer.output('result') as LogicArray).elements,
      start: 2,
    );

    addOutput('y') <= consumer.output('observed');
  }
}

/// Small structure used for sibling subset mapping regressions.
class SiblingSubsetStruct extends LogicStructure {
  final Logic low;
  final Logic high;

  factory SiblingSubsetStruct({String name = 'sibling_subset_struct'}) =>
      SiblingSubsetStruct._(
        Logic(name: 'low'),
        Logic(name: 'high'),
        name: name,
      );

  SiblingSubsetStruct._(this.low, this.high, {super.name}) : super([low, high]);

  @override
  SiblingSubsetStruct clone({String? name}) =>
      SiblingSubsetStruct(name: name ?? this.name);
}

/// Structure-output sibling variant of [SiblingSubsetProducer].
class SiblingStructSubsetProducer extends Module {
  SiblingStructSubsetProducer({super.name = 'sibling_struct_subset_producer'}) {
    final seed = addInput('seed', Logic(width: 2), width: 2);
    final result = addTypedOutput('result', SiblingSubsetStruct.new);

    result.low <= seed[0];
    result.high <= seed[1];
  }
}

/// Structure-input sibling variant of [SiblingSubsetConsumer].
class SiblingStructSubsetConsumer extends Module {
  SiblingStructSubsetConsumer({super.name = 'sibling_struct_subset_consumer'}) {
    final data = addTypedInput('data', SiblingSubsetStruct());
    addOutput('observed') <= data.high;
  }
}

/// Drives one sibling's input structure source from another sibling's output
/// structure.
class SiblingStructOutputToInputSubsetTop extends Module {
  SiblingStructOutputToInputSubsetTop()
      : super(name: 'sibling_struct_output_to_input_subset_top') {
    final source = addInput('source', Logic(width: 2), width: 2);
    final producer = SiblingStructSubsetProducer();
    producer.inputSource('seed') <= source;

    final consumer = SiblingStructSubsetConsumer();
    (consumer.inputSource('data') as SiblingSubsetStruct).assignSubset(
      (producer.output('result') as SiblingSubsetStruct).elements,
    );

    addOutput('y') <= consumer.output('observed');
  }
}

/// Inout sibling variant that exposes a net bus through a source mapping.
class SiblingInOutSubsetProducer extends Module {
  SiblingInOutSubsetProducer({super.name = 'sibling_inout_subset_producer'}) {
    addInOut('link', LogicNet(width: 4), width: 4);
  }
}

/// Inout sibling variant that observes a bit from an inout source mapping.
class SiblingInOutSubsetConsumer extends Module {
  SiblingInOutSubsetConsumer({super.name = 'sibling_inout_subset_consumer'}) {
    final data = addInOut('data', LogicNet(width: 8), width: 8);
    addOutput('observed') <= data.slice(2, 2);
  }
}

/// Drives one sibling's inout source subset from another sibling's inout
/// source.
class SiblingInOutToInOutSubsetTop extends Module {
  SiblingInOutToInOutSubsetTop()
      : super(name: 'sibling_inout_to_inout_subset_top') {
    final source = addInOut('source', LogicNet(width: 4), width: 4);
    final producer = SiblingInOutSubsetProducer();
    producer.inOutSource('link') <= source;

    final consumer = SiblingInOutSubsetConsumer();
    consumer.inOutSource('data').assignSubset([
      for (var index = 0; index < 4; index++)
        producer.inOutSource('link').slice(index, index),
    ], start: 2);

    addOutput('y') <= consumer.output('observed');
  }
}

/// Non-net (regular [Logic]) driver-direction `assignSubset`: each external bit
/// drives one bit of `sig` via `assignSubset`, and `sig` feeds a child input.
/// The intermediate `*_subset` array must be forwarded straight into the child
/// connection with no surviving `assign`.
class AssignSubsetLogicDriver extends Module {
  AssignSubsetLogicDriver(List<Logic> bits, {int n = 4})
      : super(name: 'assign_subset_logic_driver') {
    final ins = [for (var i = 0; i < n; i++) addInput('b$i', bits[i])];
    final sig = Logic(width: n, name: 'sig', naming: Naming.mergeable);
    final child = LogicInvChild(sig, n: n);
    addOutput('y', width: n) <= child.output('o');
    for (var i = 0; i < n; i++) {
      sig.assignSubset([ins[i]], start: i);
    }
  }
}

/// Partial `assignSubset`: only the low half of the child bus is driven; the
/// high half stays undriven (`z`).  Because not every element is a
/// pass-through, the intermediate `*_subset` array must be conservatively
/// preserved (no collapse) so the undriven high bits remain `z`.
class AssignSubsetPartial extends Module {
  AssignSubsetPartial(List<LogicNet> nets, LogicNet mirror, {int n = 4})
      : super(name: 'assign_subset_partial') {
    final lo = n ~/ 2;
    final netPorts = [
      for (var i = 0; i < lo; i++) addInOut('net$i', nets[i]),
    ];
    mirror = addInOut('mirror', mirror, width: n);
    final bus = LogicNet(width: n, name: 'bus', naming: Naming.mergeable);
    WholeNetBusChild(bus, mirror, n: n);
    for (var i = 0; i < lo; i++) {
      bus.assignSubset([netPorts[i]], start: i);
    }
  }
}

/// Returns the body of the last (top-level) module declaration in [sv],
/// avoiding false matches inside `endmodule`.
String _topModuleBody(String sv) {
  final matches = RegExp(r'(?:^|\n)module ').allMatches(sv).toList();
  return sv.substring(matches.last.start);
}

LogicValue _expectedPartialArrayRangeValue(int pattern,
        {required bool reversed}) =>
    _expectedSparseValue(6, pattern, (dstIndex) {
      if (dstIndex < 2 || dstIndex > 4) {
        return null;
      }
      return reversed ? 6 - dstIndex : dstIndex;
    });

LogicValue _expectedSparseValue(
  int width,
  int pattern,
  int? Function(int dstIndex) srcIndexFor,
) {
  final bits = <String>[];
  for (var dstIndex = width - 1; dstIndex >= 0; dstIndex--) {
    final srcIndex = srcIndexFor(dstIndex);
    bits.add(srcIndex == null ? 'z' : '${(pattern >> srcIndex) & 1}');
  }
  return LogicValue.ofString(bits.join());
}

LogicValue _expectedWideTemporarySlice(int pattern) =>
    LogicValue.ofInt(pattern, 96).getRange(32, 96);

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple 1d collapse', () async {
    final mod = SimpleLAPassthrough(LogicArray([4], 1));
    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, contains('assign laOut = laIn;'));
  });

  test('array collapse for cross-module connection', () async {
    final mod = ArrayTopMod(Logic());
    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, contains(RegExp(r'ArraySubModIn.*\.inp\(inp\)')));
    expect(sv, contains(RegExp(r'ArraySubModOut.*\.arrOut\(inp\)')));
  });

  test('array nets with intermediate collapse', () async {
    final mod = ArrayModuleWithNetIntermediates(
        LogicArray([3, 3], 1), LogicArray([3, 3], 1));
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect (intermediate, a);'));
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect_0 (b, intermediate);'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 123}, {'b': 123}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('partial array assignments collapse into range assignment', () async {
    final mod = PartialArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[4:2] = src[4:2];'));
    expect(topBody, isNot(contains('assign dst[2] = src[2];')));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('chained partial array range assignments collapse through intermediate',
      () async {
    final mod = ChainedPartialArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[4:2] = src[4:2];'));
    expect(topBody, isNot(contains('intermediate')));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('chained range assignment composes contained subrange offsets',
      () async {
    final mod = ChainedSubrangeArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[3:2] = src[6:5];'));
    expect(topBody, isNot(contains('intermediate')));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(
            8,
            pattern,
            (dstIndex) => dstIndex >= 2 && dstIndex <= 3 ? dstIndex + 3 : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('three-deep chained range assignments collapse iteratively', () async {
    final mod = ThreeDeepChainedPartialArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[4:2] = src[4:2];'));
    expect(topBody, isNot(contains('intermediate0')));
    expect(topBody, isNot(contains('intermediate1')));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('multi-use chained range intermediate stays expanded', () async {
    final mod = ChainedPartialArrayRangeAssignment(exposeIntermediate: true);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[4:2] = src[4:2];')));
    expect(topBody, contains('assign dst[4:2] = intermediate[4:2];'));
    expect(topBody, contains('assign intermediate[4:2] = src[4:2];'));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
          'z': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('renameable chained range intermediate stays expanded', () async {
    final mod = ChainedPartialArrayRangeAssignment(intermediateNaming: null);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[4:2] = src[4:2];')));
    expect(topBody, contains('assign dst[4:2] = intermediate[4:2];'));
    expect(topBody, contains('assign intermediate[4:2] = src[4:2];'));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('partial bus-to-array assignments collapse into range assignment',
      () async {
    final mod = PartialBusToArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[5:2] = src[5:2];'));
    expect(topBody, isNot(contains('bussubset')));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(
            8,
            pattern,
            (dstIndex) => dstIndex >= 2 && dstIndex <= 5 ? dstIndex : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('full array-to-bus assignSubset has no subset intermediate', () async {
    final mod = ArrayToBusAssignSubsetRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('_subset')));
    expect(topBody, isNot(contains('assign dst[0]')));
    expect(topBody, contains('assign dst = src[7:0];'));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({'src': pattern}, {'y': pattern})
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('partial array-to-bus assignSubset collapses into range assignment',
      () async {
    final mod = ArrayToBusAssignSubsetRangeAssignment(partial: true);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[5:2] = src[5:2];'));
    expect(topBody, isNot(contains('_subset')));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(
            8,
            pattern,
            (dstIndex) => dstIndex >= 2 && dstIndex <= 5 ? dstIndex : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  for (final config in [
    (receiverIsOutput: false, driveLowBits: true, dstName: 'dst'),
    (receiverIsOutput: true, driveLowBits: true, dstName: 'y'),
    (receiverIsOutput: false, driveLowBits: false, dstName: 'dst'),
    (receiverIsOutput: true, driveLowBits: false, dstName: 'y'),
  ]) {
    test(
        'bus slice temporary feeding assignSubset collapses into ranges '
        '(receiver is ${config.receiverIsOutput ? 'output' : 'internal'}, '
        '${config.driveLowBits ? 'full' : 'partial'} coverage)', () async {
      final mod = BusSliceTemporaryToAssignSubsetRangeAssignment(
        receiverIsOutput: config.receiverIsOutput,
        driveLowBits: config.driveLowBits,
      );
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      if (config.driveLowBits) {
        expect(topBody, contains('assign ${config.dstName}[3:0] = src[3:0];'));
      } else {
        expect(topBody, isNot(contains('assign ${config.dstName}[3:0] =')));
      }
      expect(topBody, contains('assign ${config.dstName}[7:4] = src[14:11];'));
      expect(topBody, isNot(contains('src_slice')));
      expect(topBody, isNot(contains('_subset')));

      final vectors = [
        for (final pattern in [0x0000, 0x1234, 0x5AA5, 0xFFFF])
          Vector({
            'src': pattern
          }, {
            'y': config.driveLowBits
                ? LogicValue.ofInt(
                    (pattern & 0xF) | (((pattern >> 11) & 0xF) << 4),
                    8,
                  )
                : _expectedSparseValue(
                    8,
                    pattern,
                    (dstIndex) => dstIndex >= 4 ? dstIndex + 7 : null,
                  ),
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  }

  test('bus subset helpers with extra consumers are preserved', () async {
    final mod = BusSubsetBitsWithExtraConsumers();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[3:0] = src[5:2];'));
    expect(topBody, contains(RegExp(r'\.i\([^)]*src')));

    final vectors = [
      for (final pattern in [0x00, 0x3C, 0xA5, 0xFF])
        Vector({
          'src': pattern,
        }, {
          'y': (pattern >> 2) & 0xF,
          'z': (~((pattern >> 2) & 0xF)) & 0xF,
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('partial slice helper with extra consumer is preserved', () async {
    final mod = PartialSliceWithExtraConsumer();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[8:5] = src[9:6];'));
    expect(topBody, contains('assign slice = src[11:4];'));
    expect(topBody, contains('slice[3]'));
    expect(topBody, isNot(contains(RegExp(r'assign dst\[[0-9]+\]'))));

    final vectors = [
      for (final pattern in [0x0000, 0x0080, 0x03c0, 0xffff])
        for (final enable in [0, 1])
          Vector({
            'src': pattern,
            'enable': enable,
          }, {
            'y': _expectedSparseValue(
              12,
              pattern,
              (dstIndex) =>
                  dstIndex >= 5 && dstIndex <= 8 ? dstIndex + 1 : null,
            ),
            'z': enable == 1 ? (~((pattern >> 7) & 1)) & 1 : 0,
          })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('sparse bus runs feeding assignSubset collapse independently', () async {
    final mod = SparseBusRunsToAssignSubsetRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[31:20] = srcA[15:4];'));
    expect(topBody, contains('assign dst[55:44] = srcB[11:0];'));
    expect(topBody, isNot(contains('_subset')));
    expect(topBody, isNot(contains(RegExp(r'assign dst\[[0-9]+\]'))));

    LogicValue expectedValue(int srcA, int srcB) => _expectedSparseValue(
          64,
          srcA,
          (dstIndex) => dstIndex >= 20 && dstIndex <= 31 ? dstIndex - 16 : null,
        ).withSet(
          44,
          LogicValue.ofInt(srcB & 0xfff, 12),
        );

    final vectors = [
      for (final pattern in [0x00000000, 0x12345678, 0x89abcdef])
        Vector({
          'srcA': pattern,
          'srcB': pattern >> 4,
        }, {
          'y': expectedValue(pattern, pattern >> 4),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('internal bus runs feeding assignSubset collapse through slices',
      () async {
    final mod = InternalBusRunsToAssignSubsetRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[44:13] = src[31:0];'));
    expect(topBody, isNot(contains('srcStage')));
    expect(topBody, isNot(contains('srcLow')));
    expect(topBody, isNot(contains('srcHigh')));
    expect(topBody, isNot(contains('_subset')));
    expect(topBody, isNot(contains(RegExp(r'assign dst\[[0-9]+\]'))));

    final vectors = [
      for (final pattern in [0x00000000, 0x12345678, 0x89abcdef])
        Vector({
          'src': pattern,
        }, {
          'y': _expectedSparseValue(
            64,
            pattern,
            (dstIndex) =>
                dstIndex >= 13 && dstIndex <= 44 ? dstIndex - 13 : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test(
      'computed internal bus runs feeding assignSubset collapse through '
      'slices', () async {
    final mod = InternalBusRunsToAssignSubsetRangeAssignment(
      computedSource: true,
    );
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[44:13] = srcStage[31:0];'));
    expect(topBody, isNot(contains('srcLow')));
    expect(topBody, isNot(contains('srcHigh')));
    expect(topBody, isNot(contains('_subset')));
    expect(topBody, isNot(contains(RegExp(r'assign dst\[[0-9]+\]'))));

    final vectors = [
      for (final pattern in [0x00000000, 0x12345678, 0x89abcdef])
        Vector({
          'src': pattern,
        }, {
          'y': _expectedSparseValue(
            64,
            ~pattern,
            (dstIndex) =>
                dstIndex >= 13 && dstIndex <= 44 ? dstIndex - 13 : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('wide temporary bus slice feeding array words eliminates temporary',
      () async {
    final mod = WideTemporarySliceToArrayWords();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign y[0][15:0] = src[47:32];'));
    expect(topBody, contains('assign y[1][15:0] = src[63:48];'));
    expect(topBody, contains('assign y[2][15:0] = src[79:64];'));
    expect(topBody, contains('assign y[3][15:0] = src[95:80];'));
    expect(topBody, isNot(contains('src_slice')));

    final vectors = [
      for (final pattern in [
        0,
        0x123456789abc,
        0xffffffffffff,
      ])
        Vector({
          'src': pattern,
        }, {
          'y': _expectedWideTemporarySlice(pattern),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('wide temporary slice helpers with extra consumers are preserved',
      () async {
    final mod = WideTemporarySliceToArrayWords(extraConsumers: true);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign y[0][15:0] = src[47:32];'));
    expect(topBody, contains('assign y[3][15:0] = src[95:80];'));
    expect(topBody, contains(RegExp(r'\.i\([^)]*src_slice')));

    final vectors = [
      for (final pattern in [
        0,
        0x123456789abc,
        0xffffffffffff,
      ])
        Vector({
          'src': pattern,
        }, {
          'y': _expectedWideTemporarySlice(pattern),
          'z': ~_expectedWideTemporarySlice(pattern),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('subset-like manual array name does not trigger generated subset fold',
      () async {
    final mod = ManualSubsetNamedArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('manual_subset'));
    expect(topBody, contains('assign manual_subset[4:2] = src[4:2];'));
    expect(topBody, contains('assign y = manual_subset[5:0];'));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('reordered bus-to-array assignments stay expanded', () async {
    final mod = PartialBusToArrayRangeAssignment(reversed: true);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[5:2] = src[5:2];')));
    expect(topBody, contains('assign dst[2] = src[5];'));
    expect(topBody, contains('assign dst[3] = src[4];'));
    expect(topBody, contains('assign dst[4] = src[3];'));
    expect(topBody, contains('assign dst[5] = src[2];'));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(
            8,
            pattern,
            (dstIndex) => dstIndex >= 2 && dstIndex <= 5 ? 7 - dstIndex : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('bus-to-unpacked-array assignments stay expanded', () async {
    final mod = PartialBusToArrayRangeAssignment(numUnpackedDimensions: 1);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[5:2] = src[5:2];')));
    expect(topBody, contains('assign dst[2] = src[2];'));
    expect(topBody, contains('assign dst[3] = src[3];'));
    expect(topBody, contains('assign dst[4] = src[4];'));
    expect(topBody, contains('assign dst[5] = src[5];'));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(
            8,
            pattern,
            (dstIndex) => dstIndex >= 2 && dstIndex <= 5 ? dstIndex : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
  });

  test('non-contiguous partial array assignments stay expanded', () async {
    final mod = PartialArrayRangeAssignment(reversed: true);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[4:2]')));
    expect(topBody, contains('assign dst[2] = src[4];'));
    expect(topBody, contains('assign dst[3] = src[3];'));
    expect(topBody, contains('assign dst[4] = src[2];'));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: true),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('packed multidimensional partial assignments collapse inner range',
      () async {
    final mod = PartialInnerArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[1][3:1] = src[1][3:1];'));
    expect(topBody, isNot(contains('assign dst[1][1] = src[1][1];')));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(8, pattern, (dstIndex) {
            final outerIndex = dstIndex ~/ 4;
            final innerIndex = dstIndex % 4;
            return outerIndex == 1 && innerIndex >= 1 ? dstIndex : null;
          }),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('unpacked outer dimension still collapses inner packed range', () async {
    final mod = PartialInnerArrayRangeAssignment(numUnpackedDimensions: 1);
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, contains('assign dst[1][3:1] = src[1][3:1];'));
    expect(topBody, isNot(contains(RegExp(r'assign dst\[[0-9]+:[0-9]+\]'))));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(8, pattern, (dstIndex) {
            final outerIndex = dstIndex ~/ 4;
            final innerIndex = dstIndex % 4;
            return outerIndex == 1 && innerIndex >= 1 ? dstIndex : null;
          }),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
  });

  test('unpacked one-dimensional partial assignments stay expanded', () async {
    final mod = PartialUnpackedArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[4:2] = src[4:2];')));
    expect(topBody, contains('assign dst[2] = src[2];'));
    expect(topBody, contains('assign dst[3] = src[3];'));
    expect(topBody, contains('assign dst[4] = src[4];'));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'y': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
  });

  test('wide element partial array assignments stay expanded', () async {
    final mod = PartialWideArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[2:1] = src[2:1];')));
    expect(topBody, contains('assign dst[1] = src[1];'));
    expect(topBody, contains('assign dst[2] = src[2];'));

    final vectors = [
      for (final pattern in [0x00, 0x5A, 0xA5, 0xFF])
        Vector({
          'src': pattern
        }, {
          'y': _expectedSparseValue(
            8,
            pattern,
            (dstIndex) => dstIndex >= 2 && dstIndex <= 5 ? dstIndex : null,
          ),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('net array partial assignments stay in net connection flow', () async {
    final mod = PartialNetArrayRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[4:2] = src[4:2];')));
    expect(topBody, contains('net_connect'));
    expect(topBody, contains(RegExp(r'net_connect.*\(dst\[2\], src\[2\]\)')));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'mirror': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('flat LogicNet partial assignments stay in net connection flow',
      () async {
    final mod = PartialLogicNetRangeAssignment();
    await mod.build();
    final sv = mod.generateSynth();
    final topBody = _topModuleBody(sv);

    expect(topBody, isNot(contains('assign dst[4:2] = src[4:2];')));
    expect(topBody, contains('net_connect'));

    final vectors = [
      for (final pattern in [0x00, 0x15, 0x2A, 0x3F])
        Vector({
          'src': pattern
        }, {
          'mirror': _expectedPartialArrayRangeValue(pattern, reversed: false),
        })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('array assignment non-collapsing with shuffled assignment', () async {
    final mod = ArrayWithShuffledAssignment(LogicArray([4], 1));
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv, contains('assign b[0] = a[3];'));
    expect(sv, contains('assign b[3] = a[0];'));

    final vectors = [
      Vector({'a': LogicValue.of('01xz')}, {'b': LogicValue.of('zx10')}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('array nets with intermediate collapse with unpacked', () async {
    final mod = ArrayModuleWithNetIntermediates(
        LogicArray([3, 3], 1, numUnpackedDimensions: 2),
        LogicArray([3, 3], 1, numUnpackedDimensions: 2));
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect (intermediate, a);'));
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect_0 (b, intermediate);'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 123}, {'b': 123}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
  });

  test('collapse test 2d', () async {
    final mod = ArrayModule(LogicArray([4, 4], 1));
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('assign d = c[0];'));
    expect(sv, contains('assign b = a;'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 123}, {'b': 123}),
      Vector({'c': 6}, {'d': 6}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('array element inlining', () {
    /// Expected `~a` result for the [ArrayElementFanout] configurations, where
    /// leaves are inverted and optionally consumed in [reversed] order.
    LogicValue expectedInverted(LogicValue a, int leafCount, int elementWidth,
        {required bool reversed}) {
      final leaves = [
        for (var i = 0; i < leafCount; i++)
          a.getRange(i * elementWidth, (i + 1) * elementWidth)
      ];
      return [
        for (var i = 0; i < leafCount; i++)
          ~leaves[reversed ? leafCount - 1 - i : i]
      ].rswizzle();
    }

    final fanoutConfigs = <({
      String name,
      List<int> dimensions,
      int elementWidth,
      bool reversed,
    })>[
      (name: '1d', dimensions: [4], elementWidth: 1, reversed: false),
      (name: '1d reversed', dimensions: [4], elementWidth: 1, reversed: true),
      (
        name: '1d wide elements', dimensions: [3], elementWidth: 4, //
        reversed: false
      ),
      (name: '2d', dimensions: [2, 2], elementWidth: 1, reversed: false),
      (name: '3d', dimensions: [2, 2, 2], elementWidth: 1, reversed: false),
      (
        name: '2d wide elements', dimensions: [2, 2], elementWidth: 3, //
        reversed: false
      ),
    ];

    for (final cfg in fanoutConfigs) {
      test('logic elements inline and drop the array (${cfg.name})', () async {
        final leafCount = cfg.dimensions.reduce((x, y) => x * y);
        final total = leafCount * cfg.elementWidth;

        final mod = ArrayElementFanout(Logic(width: total),
            dimensions: cfg.dimensions,
            elementWidth: cfg.elementWidth,
            reversed: cfg.reversed);
        await mod.build();
        final sv = mod.generateSynth();

        // the intermediate array (and every declaration of it) must be gone
        expect(sv, isNot(contains('arr')));

        final vectors = [
          for (final value in [0, 0xA, (1 << total) - 1])
            Vector({
              'a': value
            }, {
              'y': expectedInverted(
                  LogicValue.ofInt(value, total), leafCount, cfg.elementWidth,
                  reversed: cfg.reversed)
            })
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    final netConfigs =
        <({String name, List<int> dimensions, int elementWidth})>[
      (name: '1d', dimensions: [4], elementWidth: 1),
      (name: '2d', dimensions: [2, 2], elementWidth: 1),
      (name: '2d wide elements', dimensions: [2, 2], elementWidth: 2),
    ];

    for (final cfg in netConfigs) {
      test('net elements inline without net_connect (${cfg.name})', () async {
        final total = cfg.dimensions.reduce((x, y) => x * y) * cfg.elementWidth;

        final mod = NetArrayElementFanout(
            LogicNet(width: total), LogicNet(width: total),
            dimensions: cfg.dimensions, elementWidth: cfg.elementWidth);
        await mod.build();
        final sv = mod.generateSynth();

        // the intermediate array and its net_connects must be gone
        expect(sv, isNot(contains('arr')));
        expect(sv, isNot(contains('net_connect (arr')));

        final vectors = [
          for (final value in [0, 0xA, (1 << total) - 1])
            Vector({'a': value}, {'b': value})
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    for (final dimensions in [
      [4],
      [2, 2],
    ]) {
      test('partially-driven array is not inlined ($dimensions)', () async {
        final total = dimensions.reduce((x, y) => x * y);
        final mod = PartiallyDrivenArray(Logic(width: total - 2),
            dimensions: dimensions);
        await mod.build();
        final sv = mod.generateSynth();

        // the array must remain declared since undriven bits must stay `z`
        expect(sv, contains('arr'));

        final vectors = [
          Vector({'a': bin('01')}, {'y': LogicValue.ofString('z01z')}),
          Vector({'a': bin('10')}, {'y': LogicValue.ofString('z10z')}),
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    test('aggregate-used array is not inlined', () async {
      final mod = ArrayElementsWithAggregateUse(Logic(width: 4));
      await mod.build();
      final sv = mod.generateSynth();

      // the array stays (aggregate use), so elements are not inlined into ports
      expect(sv, contains('arr'));
      expect(sv, isNot(contains('.i((a[')));

      final vectors = [
        Vector({'a': bin('0000')}, {'y': bin('1111'), 'arrCopy': bin('0000')}),
        Vector({'a': bin('1010')}, {'y': bin('0101'), 'arrCopy': bin('1010')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('input-array port elements are not inlined away', () async {
      final mod = ArrayPortElementsToSubmodules(LogicArray([2, 2], 2));
      await mod.build();
      final sv = mod.generateSynth();

      // the array port must remain declared
      expect(sv, contains('a'));

      final vectors = [
        Vector({'a': 0}, {'y': LogicValue.ofInt(~0, 8)}),
        Vector({'a': 0xA5}, {'y': LogicValue.ofInt(~0xA5, 8)}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('struct-port array field elements are not inlined', () async {
      final mod = StructArrayFieldToSubmodules(StructWithArrayField());
      await mod.build();

      final vectors = [
        // s = {flag, arr[4]}; arr is the low 4 bits, y = ~arr
        Vector({'s': 0x00}, {'y': 0xF}),
        Vector({'s': 0x14}, {'y': 0xB}),
        Vector({'s': 0x1F}, {'y': 0x0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('aggregate connection inlining', () {
    final logicConfigs =
        <({String name, int n, int elementWidth, List<int>? perm})>[
      (name: '1d in order', n: 4, elementWidth: 1, perm: null),
      (name: '1d out of order', n: 4, elementWidth: 1, perm: [2, 3, 0, 1]),
      (name: 'wide elements', n: 3, elementWidth: 4, perm: null),
      (
        name: 'wide elements out of order',
        n: 3,
        elementWidth: 4,
        perm: [2, 0, 1]
      ),
    ];

    for (final cfg in logicConfigs) {
      test('individual signals collapse into array port (${cfg.name})',
          () async {
        final mod = IndividualSignalsToArrayPort(
            List.generate(cfg.n, (_) => Logic(width: cfg.elementWidth)),
            elementWidth: cfg.elementWidth,
            perm: cfg.perm);
        await mod.build();
        final sv = mod.generateSynth();
        final topBody = _topModuleBody(sv);

        // the intermediate array (and every per-element assignment) is gone,
        // replaced by a single inline concatenation on the child port
        expect(topBody, isNot(contains('assign')));
        expect(topBody, contains('.a(({'));

        final total = cfg.n * cfg.elementWidth;
        // element i is driven by signal perm[i] (or i), and the child
        // inverts each element; element 0 is the least-significant chunk
        LogicValue expected(int Function(int) sigVal) => [
              for (var i = 0; i < cfg.n; i++)
                ~LogicValue.ofInt(sigVal(cfg.perm == null ? i : cfg.perm![i]),
                    cfg.elementWidth)
            ].rswizzle();

        final vectors = [
          for (final pattern in [0, 1, 2])
            Vector({
              for (var i = 0; i < cfg.n; i++)
                'sig$i': (pattern * 7 + i * 3) & ((1 << cfg.elementWidth) - 1)
            }, {
              'y': expected(
                  (s) => (pattern * 7 + s * 3) & ((1 << cfg.elementWidth) - 1))
            })
        ];
        expect(total, lessThanOrEqualTo(32));
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    test('merged element sources collapse to the real source', () async {
      const n = 4;
      final mod = MergedSourcesToArrayPort(List.generate(n, (_) => Logic()));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('intermediate')));
      expect(topBody, isNot(contains('assign')));
      expect(topBody, contains('.a(({'));
      for (var i = 0; i < n; i++) {
        expect(topBody, contains('sig$i'));
      }

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF])
          Vector({
            for (var i = 0; i < n; i++) 'sig$i': (pattern >> i) & 1
          }, {
            'y': LogicValue.ofInt(~pattern, n),
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('ranged element sources are not collapsed into whole-source concat',
        () async {
      final mod = RangeSourcesToArrayPort();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains(RegExp(r'\.a\(\(\{\s*src,'))));
      expect(
        topBody,
        contains(RegExp(
            r'assign [A-Za-z_][A-Za-z0-9_$]*\[0\]\[15:0\] = src\[15:0\];')),
      );
      expect(
        topBody,
        contains(RegExp(
            r'assign [A-Za-z_][A-Za-z0-9_$]*\[3\]\[15:0\] = src\[63:48\];')),
      );

      final patterns = [
        LogicValue.filled(64, LogicValue.zero),
        LogicValue.ofInt(0x123456789abc, 64),
        LogicValue.filled(64, LogicValue.one),
      ];
      final vectors = [
        for (final pattern in patterns)
          Vector({
            'src': pattern,
          }, {
            'y': ~pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    final netConfigs = <({String name, int n, List<int>? perm})>[
      (name: '1d in order', n: 4, perm: null),
      (name: '1d out of order', n: 4, perm: [2, 3, 0, 1]),
    ];

    for (final cfg in netConfigs) {
      test('individual nets collapse into array port (${cfg.name})', () async {
        final mod = IndividualNetsToArrayPort(
            List.generate(cfg.n, (_) => LogicNet()), LogicNet(width: cfg.n),
            perm: cfg.perm);
        await mod.build();
        final sv = mod.generateSynth();
        final topBody = _topModuleBody(sv);

        // the intermediate array and its net_connects are gone, replaced by a
        // single inline concatenation on the child port
        expect(topBody, isNot(contains('net_connect')));
        expect(topBody, contains('.a(({'));

        final vectors = [
          for (final pattern in [0x0, 0xA, 0x5, 0xF])
            Vector({
              for (var i = 0; i < cfg.n; i++) 'sig$i': (pattern >> i) & 1
            }, {
              // out bit i mirrors element i, driven by signal perm[i] (or i)
              'out': [
                for (var i = 0; i < cfg.n; i++)
                  LogicValue.ofInt(
                      (pattern >> (cfg.perm == null ? i : cfg.perm![i])) & 1, 1)
              ].rswizzle()
            })
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    test('multiple aggregate uses are not collapsed', () async {
      // when the array is used as a whole more than once, the single-use
      // restriction prevents collapsing and the array stays declared
      final mod = MultiUseAggregate(List.generate(4, (_) => Logic()));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // with two whole-array uses, the array stays declared and its per-element
      // assignments remain (no inline concatenation on the ports)
      expect(topBody, contains('assign'));
      expect(topBody, isNot(contains('.a(({')));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF])
          Vector({
            for (var i = 0; i < 4; i++) 'sig$i': (pattern >> i) & 1
          }, {
            'y': (~pattern) & 0xF,
            'z': (~pattern) & 0xF,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    // The original issue was about *individual signals -> array port*; these
    // exercise the opposite shape (*array port -> individual signals*) to
    // confirm both directions generate correct SystemVerilog.
    test('array output port distributed to individual signals (logic)',
        () async {
      final mod = ArrayPortToIndividualSignals(Logic(width: 4));
      await mod.build();

      final vectors = [
        for (final x in [0x0, 0xA, 0x5, 0xF])
          Vector({
            'x': x
          }, {
            for (var i = 0; i < 4; i++) 'y$i': (~x >> i) & 1,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('array port elements collapse into individual nets (net)', () async {
      final mod = ArrayPortToIndividualNets(
          List.generate(4, (_) => LogicNet()), LogicNet(width: 4));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // the intermediate array and its net_connects collapse into a single
      // inline concatenation on the child port
      expect(topBody, isNot(contains('net_connect')));
      expect(topBody, contains('.a(({'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF])
          Vector({
            for (var i = 0; i < 4; i++) 'y$i': (pattern >> i) & 1
          }, {
            // child mirrors element i to b bit i, and element i == y$i
            'b': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('re-arrangement of one array is left to other mechanisms', () async {
      // every element source shares one common parent array, so the
      // common-parent guard skips this (no fabricated concatenation); the
      // result must still be correct.
      final mod = RearrangeOneArray(LogicArray([4], 1));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // this pass did not fabricate a consolidating concatenation on the port
      expect(topBody, isNot(contains('.a(({')));

      final vectors = [
        for (final src in [0x0, 0xA, 0x5, 0xF])
          Vector({
            'src': src
          }, {
            // arr element i = src element (3 - i); child inverts the swizzle
            'y': [
              for (var i = 0; i < 4; i++)
                ~LogicValue.ofInt((src >> (3 - i)) & 1, 1)
            ].rswizzle()
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('expressionless array port is not inlined into', () async {
      // the child's array port is declared expressionless, so no concatenation
      // may be inlined into it; the array and its assignments must remain.
      final mod = IndividualSignalsToExpressionlessPort(
          List.generate(4, (_) => Logic()));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // no inline concatenation on the expressionless port; per-element
      // assignments to the intermediate array remain
      expect(topBody, isNot(contains('.a(({')));
      expect(topBody, contains('assign'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF])
          Vector({
            for (var i = 0; i < 4; i++) 'sig$i': (pattern >> i) & 1
          }, {
            'y': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('flat net bus collapsing', () {
    test('cleared bus subsets do not claim better surviving basenames',
        () async {
      final mod = WholeNetBusCollapseNamingCollision();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('bussubset (')));
      expect(topBody, contains('logic bussubset;'));
      expect(topBody, isNot(contains('bussubset_')));
      expect(topBody, contains('.data(({'));
    },
        skip: 'Known issue: BusSubset instances that are later cleared by '
            'whole-net-bus collapse can still claim names before surviving '
            'signals.');

    // Case A: a flat net bus tied bit-by-bit to individual nets and passed as a
    // whole to a child inout port collapses into a single inline concatenation
    // of those nets.
    for (final busNaming in [Naming.mergeable, Naming.renameable]) {
      test('whole net bus to port collapses ($busNaming)', () async {
        const n = 8;
        final mod = WholeNetBusToPort(
            List.generate(n, (_) => LogicNet()), LogicNet(width: n),
            busNaming: busNaming);
        await mod.build();
        final sv = mod.generateSynth();
        final topBody = _topModuleBody(sv);

        // the bus and its per-bit net_connects are gone, replaced by a single
        // inline concatenation on the child port
        expect(topBody, isNot(contains('net_connect')));
        expect(topBody, isNot(contains('wire [7:0] bus')));
        expect(topBody, contains('.data(({'));

        final vectors = [
          for (final pattern in [0x0, 0xA, 0x5, 0xFF, 0x3C])
            Vector({
              for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
            }, {
              'mirror': pattern,
            })
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    test('whole net bus collapse preserves inline subset consumers', () async {
      const n = 4;
      final mod = WholeNetBusToPortWithInlineSubsetConsumer(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, contains('.data'));
      expect(topBody, contains('enable &'));

      final vectors = [
        for (final enable in [0, 1])
          for (final pattern in [0x0, 0x5, 0xA, 0xF])
            Vector({
              'enable': enable,
              for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1,
            }, {
              'mirror': pattern,
              'z': enable == 0 ? 0 : (~pattern) & 1,
            })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('whole net bus collapse ignores read-only subset consumers', () async {
      const n = 4;
      final mod =
          WholeNetBusToPortWithReadOnlyInlineSubsetConsumer(LogicNet(width: n));
      await mod.build();
      final topBody = _topModuleBody(mod.generateSynth());

      expect(topBody, contains('wire [3:0] bus'));
      expect(topBody, contains(RegExp('net_connect.*_subset_0_0_bus')));
      expect(topBody, contains('enable &'));
    });

    test('reserved-named whole net bus is not collapsed', () async {
      const n = 8;
      final mod = WholeNetBusToPort(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n),
          busNaming: Naming.reserved);
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // a reserved name must be preserved, so the bus and its net_connects stay
      expect(topBody, contains('bus'));
      expect(topBody, contains('net_connect'));
      expect(topBody, isNot(contains('.data(({')));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0xFF])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('multiply-used whole net bus is not collapsed', () async {
      const n = 8;
      final mod = WholeNetBusMultiUse(List.generate(n, (_) => LogicNet()),
          LogicNet(width: n), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // used as a whole twice, so the single-use restriction keeps the bus
      expect(topBody, contains('bus'));
      expect(topBody, contains('net_connect'));
      expect(topBody, isNot(contains('.data(({')));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0xFF])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror1': pattern,
            'mirror2': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    // Case B: a flat net bus tied bit-by-bit to individual nets and passed to a
    // child inout *array* port traces through the pass-through bus and
    // collapses into a single inline concatenation of those nets.
    for (final busNaming in [Naming.mergeable, Naming.renameable]) {
      test('bitwise net bus into array port collapses ($busNaming)', () async {
        const n = 8;
        final mod = BitwiseNetBusToArrayPort(
            List.generate(n, (_) => LogicNet()), LogicNet(width: n),
            busNaming: busNaming);
        await mod.build();
        final sv = mod.generateSynth();
        final topBody = _topModuleBody(sv);

        // the bus and its net_connects are traced away and replaced by a
        // single inline concatenation of those nets on the child array port
        expect(topBody, isNot(contains('net_connect')));
        expect(topBody, isNot(contains('wire [7:0] bus')));
        expect(topBody, contains('.data(({'));

        final vectors = [
          for (final pattern in [0x0, 0xA, 0x5, 0xFF, 0x3C])
            Vector({
              for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
            }, {
              'mirror': pattern,
            })
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    test('bitwise net bus collapse preserves inline subset consumers',
        () async {
      const n = 4;
      final mod = BitwiseNetBusToArrayPortWithInlineSubsetConsumer(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, contains('.data'));
      expect(topBody, contains('enable &'));

      final vectors = [
        for (final enable in [0, 1])
          for (final pattern in [0x0, 0x5, 0xA, 0xF])
            Vector({
              'enable': enable,
              for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1,
            }, {
              'mirror': pattern,
              'z': enable == 0 ? 0 : (~pattern) & 1,
            })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('reserved-named bitwise net bus into array port is not collapsed',
        () async {
      const n = 8;
      final mod = BitwiseNetBusToArrayPort(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n),
          busNaming: Naming.reserved);
      await mod.build();
      final sv = mod.generateSynth();

      // a reserved bus name must be preserved, so it is not traced away
      expect(sv, contains('bus'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0xFF])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    // Corner case: a bit connected to *another bit of the same bus*.  When that
    // bit is also externally driven, it gets a second `BusSubset` definer, so
    // the "each bit driven exactly once" guard must keep the bus intact.
    for (final toArray in [false, true]) {
      test('self-bit-connected net bus is not collapsed (toArray=$toArray)',
          () async {
        const n = 8;
        final mod = SelfBitNetBus(
            List.generate(n, (_) => LogicNet()), LogicNet(width: n),
            toArray: toArray);
        await mod.build();
        final sv = mod.generateSynth();
        final topBody = _topModuleBody(sv);

        // the self-connection leaves a per-bit net_connect structure intact
        expect(topBody, contains('net_connect'));
        expect(topBody, isNot(contains('.data(({')));

        final vectors = [
          for (final pattern in [0x0, 0x2A, 0x55, 0x7F])
            Vector({
              // only the lower n-1 bits are externally driven
              for (var i = 0; i < n - 1; i++) 'net$i': (pattern >> i) & 1
            }, {
              // bits 0..n-2 mirror their nets; the top bit follows bit 0
              'mirror':
                  (pattern & ((1 << (n - 1)) - 1)) | ((pattern & 1) << (n - 1)),
            })
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    // Corner case: a pure self-loop (bit1 <= bit0, no other drivers) merges
    // both bits into a single standalone net and may safely collapse without
    // producing a dangling reference to the deleted bus.
    for (final toArray in [false, true]) {
      test('pure self-loop net bus collapses safely (toArray=$toArray)',
          () async {
        final mod = PureSelfLoopNetBus(LogicNet(width: 2), toArray: toArray);
        await mod.build();
        final sv = mod.generateSynth();
        final topBody = _topModuleBody(sv);

        // the bus collapses into an inline concatenation of the merged net, and
        // the swizzle must not reference a now-deleted bus slice
        expect(topBody, isNot(contains('net_connect')));
        expect(topBody, isNot(contains('wire [1:0] bus')));
        expect(topBody, contains('.data(({'));
      });
    }
  });

  group('assignSubset pass-through forwarding', () {
    // The `connectPorts(top.bit_i, child.netPort[i])` receiver scenario:
    // `assignSubset` ties each external bit net into one bit of a child's net
    // bus.  The intermediate `*_subset` net array must be forwarded away so the
    // whole connection becomes a single inline concatenation with no per-bit
    // `net_connect`.
    test('per-bit assignSubset into whole net bus collapses', () async {
      const n = 4;
      final mod = AssignSubsetReceiver(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // no intermediate subset array, and no per-bit net_connects remain
      expect(topBody, isNot(contains('_subset')));
      expect(topBody, isNot(contains('net_connect')));
      expect(topBody, contains('.data(({'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF, 0x3])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('scrambled-order assignSubset preserves per-bit positions', () async {
      const n = 4;
      final mod = AssignSubsetReceiverScrambled(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('_subset')));
      expect(topBody, isNot(contains('net_connect')));
      expect(topBody, contains('.data(({'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF, 0x6])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('renameable subset target is still forwarded but bus is preserved',
        () async {
      const n = 4;
      final mod = AssignSubsetReceiver(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n),
          busNaming: Naming.renameable);
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // the named bus is preserved, but the per-bit `*_subset` pass-through and
      // its per-bit net_connects are still forwarded away (a single net_connect
      // carries the whole inline concatenation onto the bus)
      expect(topBody, isNot(contains('_subset')));
      expect(topBody, contains('bus'));
      expect(topBody, contains('({'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0xF])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('driver-direction assignSubset into whole net bus collapses',
        () async {
      const n = 4;
      final mod = AssignSubsetDriver(
          List.generate(n, (_) => LogicNet()), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // the per-bit `*_subset` pass-throughs and per-bit `net_connect`s are
      // forwarded away so the whole connection is a single inline concatenation
      expect(topBody, isNot(contains('_subset')));
      expect(topBody, isNot(contains('net_connect')));
      expect(topBody, contains('.data(({'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF, 0x3])
          Vector({
            for (var i = 0; i < n; i++) 'net$i': (pattern >> i) & 1
          }, {
            'mirror': pattern,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('non-net assignSubset driver forwards into child input', () async {
      const n = 4;
      final mod = AssignSubsetLogicDriver(List.generate(n, (_) => Logic()));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // the intermediate `sig_subset` array is forwarded straight into the
      // child input with no surviving per-bit `assign`
      expect(topBody, isNot(contains('_subset')));
      expect(topBody, isNot(contains('assign')));
      expect(topBody, contains('.i(({'));

      final vectors = [
        for (final pattern in [0x0, 0xA, 0x5, 0xF, 0x6])
          Vector({
            for (var i = 0; i < n; i++) 'b$i': (pattern >> i) & 1
          }, {
            'y': (~pattern) & 0xF,
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('assignSubset into late child input source maps instance input',
        () async {
      final mod = LateSubsetInputTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, contains('.data(source)'));

      final vectors = [
        for (final pattern in [0x00, 0x01, 0x02, 0xff])
          Vector({'source': pattern}, {'y': pattern & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('assignSubset slice into late child input source keeps mapping',
        () async {
      final mod = LateSlicedSubsetInputTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, contains('assign'));
      expect(topBody, contains('source[11:4]'));

      final vectors = [
        for (final pattern in [0x0000, 0x0010, 0x00f0, 0xffff])
          Vector({'source': pattern}, {'y': (pattern >> 4) & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('sibling output can drive subset of sibling input source', () async {
      final mod = SiblingOutputToInputSubsetTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, isNot(contains('.result()')));

      final vectors = [
        for (final pattern in [0x0, 0x1, 0x2, 0xf])
          Vector({'source': pattern}, {'y': pattern & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('sibling full output can drive sibling full input source', () async {
      final mod = SiblingFullOutputToInputSubsetTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, isNot(contains('.result()')));

      final vectors = [
        for (final pattern in [0x0, 0x1, 0x2, 0xf])
          Vector({'source': pattern}, {'y': pattern & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('sibling output array can drive subset of sibling input array source',
        () async {
      final mod = SiblingArrayOutputToInputSubsetTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, isNot(contains('.result()')));

      final vectors = [
        for (final pattern in [0x0, 0x1, 0x2, 0xf])
          Vector({'source': pattern}, {'y': pattern & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('sibling output structure can drive sibling input structure source',
        () async {
      final mod = SiblingStructOutputToInputSubsetTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, isNot(contains('.result()')));

      final vectors = [
        for (final pattern in [0x0, 0x1, 0x2, 0x3])
          Vector({'source': pattern}, {'y': (pattern >> 1) & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('sibling inout can drive subset of sibling inout source', () async {
      final mod = SiblingInOutToInOutSubsetTop();
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      expect(topBody, isNot(contains('.data()')));
      expect(topBody, isNot(contains('.link()')));

      final vectors = [
        for (final pattern in [0x0, 0x1, 0x2, 0xf])
          Vector({'source': pattern}, {'y': pattern & 1})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('partial assignSubset is conservatively preserved (undriven stays z)',
        () async {
      const n = 4;
      final mod = AssignSubsetPartial(
          List.generate(n ~/ 2, (_) => LogicNet()), LogicNet(width: n));
      await mod.build();
      final sv = mod.generateSynth();
      final topBody = _topModuleBody(sv);

      // not every element is a pass-through, so the subset array is preserved
      expect(topBody, contains('_subset'));
      expect(topBody, contains('bus_subset[3'));
      expect(topBody, contains('net_connect'));

      final vectors = [
        for (final pattern in [0x0, 0x1, 0x2, 0x3])
          Vector({
            for (var i = 0; i < n ~/ 2; i++) 'net$i': (pattern >> i) & 1
          }, {
            // high half is undriven => z, low half mirrors the driven bits
            'mirror': 'zz${(pattern >> 1) & 1}${pattern & 1}',
          })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('kitchen-sink collapse combinations', () {
    // Enumerate every valid combination of the independent collapse toggles for
    // both nets and non-nets.  For every combination we always check functional
    // correctness (functional + iverilog), and for the combinations whose
    // structure we can confidently predict we also assert the generated
    // SystemVerilog looks the way it should.  The cost of a silent corner-case
    // bug here is high, so coverage is intentionally exhaustive.
    final configs = <CollapseConfig>[];
    for (final isNet in [true, false]) {
      final mechanisms =
          isNet ? TieMechanism.values : const [TieMechanism.subsetReceiver];
      for (final mechanism in mechanisms) {
        for (final toArray in [false, true]) {
          for (final scrambled in [false, true]) {
            for (final collapsibleBus in [true, false]) {
              // partial drive only has well-defined `z` semantics for nets
              for (final partial in isNet ? [false, true] : [false]) {
                for (final multiUse in [false, true]) {
                  configs.add(CollapseConfig(
                    isNet: isNet,
                    mechanism: mechanism,
                    toArray: toArray,
                    scrambled: scrambled,
                    collapsibleBus: collapsibleBus,
                    partial: partial,
                    multiUse: multiUse,
                  ));
                }
              }
            }
          }
        }
      }
    }

    for (final config in configs) {
      test(config.description, () async {
        const n = CollapseConfig.width;
        final k = config.driven;
        final reason = config.description;

        final Module mod;
        final List<Vector> vectors;
        if (config.isNet) {
          final netMod = NetKitchenSink(
            config,
            List.generate(k, (_) => LogicNet()),
            LogicNet(width: n),
            config.multiUse ? LogicNet(width: n) : null,
          );
          mod = netMod;
          String expected(int pattern) => config.partial
              ? ('z' * (n - k)) + pattern.toRadixString(2).padLeft(k, '0')
              : LogicValue.ofInt(pattern, n).toString(includeWidth: false);
          final patterns =
              config.partial ? [0x0, 0x1, 0x2, 0x3] : [0x0, 0xA, 0x5, 0xF, 0x6];
          vectors = [
            for (final pattern in patterns)
              Vector({
                for (var i = 0; i < k; i++) 'net$i': (pattern >> i) & 1,
              }, {
                'mirror1': expected(pattern),
                if (config.multiUse) 'mirror2': expected(pattern),
              }),
          ];
        } else {
          final logicMod =
              LogicKitchenSink(config, List.generate(n, (_) => Logic()));
          mod = logicMod;
          final patterns = [0x0, 0xA, 0x5, 0xF, 0x6];
          vectors = [
            for (final pattern in patterns)
              Vector({
                for (var i = 0; i < n; i++) 'b$i': (pattern >> i) & 1,
              }, {
                'y': pattern,
                if (config.multiUse) 'y2': pattern,
              }),
          ];
        }

        await mod.build();
        final topBody = _topModuleBody(mod.generateSynth());

        // --- structural expectations (only where confidently predictable) ---
        if (config.noSubset) {
          expect(topBody, isNot(contains('_subset')),
              reason: 'subset pass-throughs should be forwarded away: $reason');
        }

        if (config.fullyCollapses) {
          expect(topBody, isNot(contains(RegExp(r'\bbus\b'))),
              reason: 'mergeable bus should dissolve entirely: $reason');
          expect(topBody, contains('.data(({'),
              reason: 'an inline concatenation should drive the child: '
                  '$reason');
          if (config.isNet) {
            expect(topBody, isNot(contains('net_connect')),
                reason: 'no per-bit net_connect should remain: $reason');
          }
        }

        // --- functional correctness (always) ---
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }
  });
}

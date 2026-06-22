// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array_sim_test.dart
// Simulation tests for LogicArray with Iverilog and SystemC backends.
// Exercises sequential logic, element-wise operations, and submodule
// hierarchy with array ports — scenarios beyond the combinational
// passthrough tests in logic_array_test.dart.
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// Flops each element of a LogicArray independently.
/// Tests sequential (clocked) array element access in generated code.
class ArrayFlopModule extends Module {
  LogicArray get dataOut => output('dataOut') as LogicArray;

  ArrayFlopModule(LogicArray dataIn, {required Logic reset})
      : super(name: 'ArrayFlopModule') {
    final clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    dataIn = addInputArray('dataIn', dataIn,
        dimensions: dataIn.dimensions, elementWidth: dataIn.elementWidth);

    final out = addOutputArray('dataOut',
        dimensions: dataIn.dimensions, elementWidth: dataIn.elementWidth);

    for (var i = 0; i < dataIn.dimensions[0]; i++) {
      out.elements[i] <= flop(clk, dataIn.elements[i], reset: reset);
    }
  }
}

/// Applies bitwise NOT to each element, then passes through a submodule.
/// Tests combinational element-wise ops + array hierarchy.
class ArrayInvertAndPassModule extends Module {
  LogicArray get dataOut => output('dataOut') as LogicArray;

  ArrayInvertAndPassModule(LogicArray dataIn)
      : super(name: 'ArrayInvertAndPassModule') {
    dataIn = addInputArray('dataIn', dataIn,
        dimensions: dataIn.dimensions, elementWidth: dataIn.elementWidth);

    final inverted =
        LogicArray(dataIn.dimensions, dataIn.elementWidth, name: 'inverted');
    for (var i = 0; i < dataIn.dimensions[0]; i++) {
      inverted.elements[i] <= ~dataIn.elements[i];
    }

    // Pass through a sub-module to exercise array port wiring
    final sub = _ArrayPassSub(inverted);

    addOutputArray('dataOut',
            dimensions: dataIn.dimensions, elementWidth: dataIn.elementWidth) <=
        sub.out;
  }
}

class _ArrayPassSub extends Module {
  LogicArray get out => output('out') as LogicArray;

  _ArrayPassSub(LogicArray inp) : super(name: 'ArrayPassSub') {
    inp = addInputArray('inp', inp,
        dimensions: inp.dimensions, elementWidth: inp.elementWidth);
    addOutputArray('out',
            dimensions: inp.dimensions, elementWidth: inp.elementWidth) <=
        inp;
  }
}

/// Muxes between two LogicArray inputs based on a select signal.
/// Tests conditional array assignment in generated code.
class ArrayMuxModule extends Module {
  LogicArray get dataOut => output('dataOut') as LogicArray;

  ArrayMuxModule(LogicArray a, LogicArray b, Logic sel)
      : super(name: 'ArrayMuxModule') {
    a = addInputArray('a', a,
        dimensions: a.dimensions, elementWidth: a.elementWidth);
    b = addInputArray('b', b,
        dimensions: b.dimensions, elementWidth: b.elementWidth);
    sel = addInput('sel', sel);

    final out = addOutputArray('dataOut',
        dimensions: a.dimensions, elementWidth: a.elementWidth);

    Combinational([
      If(sel, then: [out < a], orElse: [out < b]),
    ]);
  }
}

/// Concatenates two array elements into a wider output and also
/// provides a reduced (OR-reduce) output across array elements.
/// Tests mixed array-element and scalar operations.
class ArrayReduceModule extends Module {
  Logic get concat01 => output('concat01');
  Logic get anyNonZero => output('anyNonZero');

  ArrayReduceModule(LogicArray dataIn) : super(name: 'ArrayReduceModule') {
    dataIn = addInputArray('dataIn', dataIn,
        dimensions: dataIn.dimensions, elementWidth: dataIn.elementWidth);

    final c = addOutput('concat01', width: dataIn.elementWidth * 2);
    final a = addOutput('anyNonZero');

    // Concatenate elements [1] and [0]
    c <= [dataIn.elements[1], dataIn.elements[0]].swizzle();

    // OR-reduce: is any element non-zero?
    a <= dataIn.elements.map((e) => e.or()).toList().swizzle().or();
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  tearDownAll(() => SimCompare.cleanupSystemCCache(keepPch: false));

  group('LogicArray simulation', () {
    group('sequential flop per element', () {
      test('1D array of 4x8-bit', () async {
        final reset = Logic(name: 'reset');
        final dataIn = LogicArray([4], 8);
        final mod = ArrayFlopModule(dataIn, reset: reset);
        await mod.build();

        // Each element is flopped: output appears one cycle after input.
        // Vector check is BEFORE posedge → sees PREVIOUS cycle's result.
        final vectors = [
          Vector({'reset': 1, 'dataIn': 0}, {}),
          Vector({'reset': 1, 'dataIn': 0}, {}),
          Vector({'reset': 1, 'dataIn': 0}, {'dataOut': 0}),
          // Deassert reset; still see 0 from reset phase
          Vector({'reset': 0, 'dataIn': 0x44332211}, {'dataOut': 0x00000000}),
          // Now see 0x44332211 from previous cycle
          Vector({'reset': 0, 'dataIn': 0xDDCCBBAA}, {'dataOut': 0x44332211}),
          Vector({'reset': 0, 'dataIn': 0x00000000}, {'dataOut': 0xDDCCBBAA}),
          Vector({'reset': 0, 'dataIn': 0x00000000}, {'dataOut': 0x00000000}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
        SimCompare.checkSystemCVector(mod, vectors);
      });
    });

    group('element-wise invert with submodule', () {
      test('1D array of 3x8-bit', () async {
        final dataIn = LogicArray([3], 8);
        final mod = ArrayInvertAndPassModule(dataIn);
        await mod.build();

        // 0x00 → 0xFF, 0xAA → 0x55, 0x0F → 0xF0
        // Input:  0x0FAA00 (elem[0]=0x00, elem[1]=0xAA, elem[2]=0x0F)
        // Output: 0xF055FF (elem[0]=0xFF, elem[1]=0x55, elem[2]=0xF0)
        final vectors = [
          Vector({'dataIn': 0x0FAA00}, {'dataOut': 0xF055FF}),
          Vector({'dataIn': 0xFFFFFF}, {'dataOut': 0x000000}),
          Vector({'dataIn': 0x000000}, {'dataOut': 0xFFFFFF}),
          Vector({
            'dataIn': 0x123456
          }, {
            'dataOut': LogicValue.ofInt(0x123456, 24) ^
                LogicValue.filled(24, LogicValue.one)
          }),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
        SimCompare.checkSystemCVector(mod, vectors);
      });

      test('1D array of 2x4-bit', () async {
        final dataIn = LogicArray([2], 4);
        final mod = ArrayInvertAndPassModule(dataIn);
        await mod.build();

        final vectors = [
          Vector({'dataIn': 0x00}, {'dataOut': 0xFF}),
          Vector({'dataIn': 0xAB}, {'dataOut': 0x54}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
        SimCompare.checkSystemCVector(mod, vectors);
      });
    });

    group('array mux', () {
      test('1D array of 3x8-bit', () async {
        final a = LogicArray([3], 8);
        final b = LogicArray([3], 8);
        final sel = Logic(name: 'sel');
        final mod = ArrayMuxModule(a, b, sel);
        await mod.build();

        final vectors = [
          // sel=1 → output = a
          Vector(
              {'sel': 1, 'a': 0x112233, 'b': 0xAABBCC}, {'dataOut': 0x112233}),
          // sel=0 → output = b
          Vector(
              {'sel': 0, 'a': 0x112233, 'b': 0xAABBCC}, {'dataOut': 0xAABBCC}),
          // Toggle
          Vector(
              {'sel': 1, 'a': 0xFFFFFF, 'b': 0x000000}, {'dataOut': 0xFFFFFF}),
          Vector(
              {'sel': 0, 'a': 0xFFFFFF, 'b': 0x000000}, {'dataOut': 0x000000}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
        SimCompare.checkSystemCVector(mod, vectors);
      });
    });

    group('array reduce and concat', () {
      test('1D array of 4x8-bit', () async {
        final dataIn = LogicArray([4], 8);
        final mod = ArrayReduceModule(dataIn);
        await mod.build();

        // Elements: [0]=low 8 bits, [1]=next 8, etc.
        // concat01 = {elem[1], elem[0]} (16 bits)
        // anyNonZero = OR-reduce of all elements
        final vectors = [
          // All zero
          Vector({'dataIn': 0x00000000}, {'concat01': 0x0000, 'anyNonZero': 0}),
          // elem[0]=0x01
          Vector({'dataIn': 0x00000001}, {'concat01': 0x0001, 'anyNonZero': 1}),
          // elem[0]=0xAB, elem[1]=0xCD
          Vector({'dataIn': 0x0000CDAB}, {'concat01': 0xCDAB, 'anyNonZero': 1}),
          // elem[3]=0xFF only (upper byte)
          Vector({'dataIn': 0xFF000000}, {'concat01': 0x0000, 'anyNonZero': 1}),
          // All 0xFF
          Vector({'dataIn': 0xFFFFFFFF}, {'concat01': 0xFFFF, 'anyNonZero': 1}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
        SimCompare.checkSystemCVector(mod, vectors);
      });
    });
  });
}

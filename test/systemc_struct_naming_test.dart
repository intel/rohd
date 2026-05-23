// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_struct_naming_test.dart
// Tests for SystemC generation with various LogicStructure/Interface port
// patterns that exercise _BusSubsetForStructSlice and SynthLogic naming.
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test structures and modules
// ─────────────────────────────────────────────────────────────────────────────

/// A simple 2-field LogicStructure.
class TwoFieldStruct extends LogicStructure {
  late final Logic data;
  late final Logic valid;

  TwoFieldStruct({int dataWidth = 4, String? name})
      : super([
          Logic(name: 'data', width: dataWidth),
          Logic(name: 'valid'),
        ], name: name ?? 'twoField') {
    data = elements[0];
    valid = elements[1];
  }

  @override
  TwoFieldStruct clone({String? name}) => TwoFieldStruct(
        dataWidth: data.width,
        name: name ?? this.name,
      );
}

/// A 3-field struct to test wider slicing.
class ThreeFieldStruct extends LogicStructure {
  late final Logic a;
  late final Logic b;
  late final Logic c;

  ThreeFieldStruct({int width = 4, String? name})
      : super([
          Logic(name: 'a', width: width),
          Logic(name: 'b', width: width),
          Logic(name: 'c', width: width),
        ], name: name ?? 'threeField') {
    a = elements[0];
    b = elements[1];
    c = elements[2];
  }

  @override
  ThreeFieldStruct clone({String? name}) =>
      ThreeFieldStruct(width: a.width, name: name ?? this.name);
}

/// A nested struct: outer contains an inner TwoFieldStruct plus extra signal.
class NestedStruct extends LogicStructure {
  late final Logic inner;
  late final Logic extra;

  NestedStruct({int dataWidth = 4, String? name})
      : super([
          TwoFieldStruct(dataWidth: dataWidth, name: 'inner'),
          Logic(name: 'extra', width: 2),
        ], name: name ?? 'nested') {
    inner = elements[0];
    extra = elements[1];
  }

  @override
  NestedStruct clone({String? name}) => NestedStruct(
      dataWidth: (elements[0] as LogicStructure).elements[0].width,
      name: name ?? this.name);
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 1: Module with a LogicStructure INPUT port
// ─────────────────────────────────────────────────────────────────────────────

/// Module that takes a LogicStructure input and uses individual fields.
class StructInputModule extends Module {
  Logic get dataOut => output('dataOut');
  Logic get validOut => output('validOut');

  StructInputModule(TwoFieldStruct structIn)
      : super(
            name: 'structInputMod',
            definitionName: 'StructInputModule_W${structIn.data.width}') {
    structIn = addTypedInput('structIn', structIn);
    final dataOut = addOutput('dataOut', width: structIn.data.width);
    final validOut = addOutput('validOut');
    dataOut <= structIn.data;
    validOut <= structIn.valid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 2: Module with a LogicStructure OUTPUT port
// ─────────────────────────────────────────────────────────────────────────────

/// Module that produces a LogicStructure output from scalar inputs.
class StructOutputModule extends Module {
  late final TwoFieldStruct structOut;

  StructOutputModule(Logic data, Logic valid)
      : super(
            name: 'structOutputMod',
            definitionName: 'StructOutputModule_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);
    structOut = addTypedOutput(
        'structOut', TwoFieldStruct(dataWidth: data.width).clone);
    structOut.data <= data;
    structOut.valid <= valid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 3: Sub-module with LogicStructure output consumed by parent
// ─────────────────────────────────────────────────────────────────────────────

/// Parent module that instantiates StructOutputModule and reads its struct out.
class ParentOfStructOutput extends Module {
  Logic get dataOut => output('dataOut');
  Logic get validOut => output('validOut');

  ParentOfStructOutput(Logic data, Logic valid)
      : super(
            name: 'parentOfStructOutput',
            definitionName: 'ParentOfStructOutput_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    final sub = StructOutputModule(data, valid);
    final dataOut = addOutput('dataOut', width: data.width);
    final validOut = addOutput('validOut');
    dataOut <= sub.structOut.data;
    validOut <= sub.structOut.valid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 4: Sub-module with LogicStructure input fed by parent
// ─────────────────────────────────────────────────────────────────────────────

/// Parent module that builds a struct and feeds it to StructInputModule.
class ParentOfStructInput extends Module {
  Logic get dataOut => output('dataOut');
  Logic get validOut => output('validOut');

  ParentOfStructInput(Logic data, Logic valid)
      : super(
            name: 'parentOfStructInput',
            definitionName: 'ParentOfStructInput_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    final structSig = TwoFieldStruct(dataWidth: data.width, name: 'myStruct');
    structSig.data <= data;
    structSig.valid <= valid;

    final sub = StructInputModule(structSig);
    final dataOut = addOutput('dataOut', width: data.width);
    final validOut = addOutput('validOut');
    dataOut <= sub.dataOut;
    validOut <= sub.validOut;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 5: Chained sub-modules with struct passthrough
// ─────────────────────────────────────────────────────────────────────────────

/// Sub-module that passes through a struct (input struct → output struct).
class StructPassthrough extends Module {
  late final TwoFieldStruct structOut;

  StructPassthrough(TwoFieldStruct structIn)
      : super(
            name: 'structPass',
            definitionName: 'StructPassthrough_W${structIn.data.width}') {
    structIn = addTypedInput('structIn', structIn);
    structOut = addTypedOutput('structOut', structIn.clone);
    structOut <= structIn;
  }
}

/// Parent with two chained StructPassthrough sub-modules.
class ChainedStructPassthrough extends Module {
  Logic get dataOut => output('dataOut');

  ChainedStructPassthrough(Logic data, Logic valid)
      : super(
            name: 'chainedStruct',
            definitionName: 'ChainedStructPassthrough_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    final struct1 = TwoFieldStruct(dataWidth: data.width, name: 'struct1');
    struct1.data <= data;
    struct1.valid <= valid;

    final pass1 = StructPassthrough(struct1);
    final pass2 = StructPassthrough(pass1.structOut);

    final dataOut = addOutput('dataOut', width: data.width);
    dataOut <= pass2.structOut.data;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 6: Three-field struct (wider slicing pattern)
// ─────────────────────────────────────────────────────────────────────────────

/// Module with a 3-field struct output, partially consumed by parent.
class ThreeFieldOutputModule extends Module {
  late final ThreeFieldStruct structOut;

  ThreeFieldOutputModule(Logic a, Logic b, Logic c)
      : super(
            name: 'threeFieldOut',
            definitionName: 'ThreeFieldOutputModule_W${a.width}') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    c = addInput('c', c, width: c.width);
    structOut =
        addTypedOutput('structOut', ThreeFieldStruct(width: a.width).clone);
    structOut.a <= a;
    structOut.b <= b;
    structOut.c <= c;
  }
}

/// Parent that only uses SOME fields of the 3-field struct output.
class PartialStructConsumer extends Module {
  Logic get sumOut => output('sumOut');

  PartialStructConsumer(Logic a, Logic b, Logic c)
      : super(
            name: 'partialConsumer',
            definitionName: 'PartialStructConsumer_W${a.width}') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    c = addInput('c', c, width: c.width);

    final sub = ThreeFieldOutputModule(a, b, c);
    // Only consume .a and .c, leaving .b unused
    final sumOut = addOutput('sumOut', width: a.width);
    sumOut <= sub.structOut.a + sub.structOut.c;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 7: Struct with gates operating on fields
// ─────────────────────────────────────────────────────────────────────────────

/// Module that takes a struct input and performs gate operations on fields.
class StructGateModule extends Module {
  Logic get result => output('result');

  StructGateModule(TwoFieldStruct structIn)
      : super(
            name: 'structGate',
            definitionName: 'StructGateModule_W${structIn.data.width}') {
    structIn = addTypedInput('structIn', structIn);
    final result = addOutput('result', width: structIn.data.width);
    // Gate operations on struct fields
    result <= mux(structIn.valid, structIn.data, Const(0, width: result.width));
  }
}

/// Parent that creates a struct and feeds it into StructGateModule.
class ParentOfStructGate extends Module {
  Logic get result => output('result');

  ParentOfStructGate(Logic data, Logic valid)
      : super(
            name: 'parentStructGate',
            definitionName: 'ParentOfStructGate_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    final s = TwoFieldStruct(dataWidth: data.width, name: 'mySig');
    s.data <= data;
    s.valid <= valid;

    final sub = StructGateModule(s);
    final result = addOutput('result', width: data.width);
    result <= sub.result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 8: Sequential module with struct input
// ─────────────────────────────────────────────────────────────────────────────

/// Module with a struct input and a flop on the data field.
class StructFlopModule extends Module {
  Logic get qOut => output('qOut');

  StructFlopModule(TwoFieldStruct structIn, {Logic? reset})
      : super(
            name: 'structFlop',
            definitionName: 'StructFlopModule_W${structIn.data.width}') {
    if (reset != null) {
      reset = addInput('reset', reset);
    }
    structIn = addTypedInput('structIn', structIn);
    final qOut = addOutput('qOut', width: structIn.data.width);
    final clk = SimpleClockGenerator(10).clk;
    // Only flop the data field when valid is high
    qOut <= flop(clk, structIn.data, reset: reset, en: structIn.valid);
  }
}

/// Parent that drives StructFlopModule from scalar signals.
class ParentOfStructFlop extends Module {
  Logic get qOut => output('qOut');

  ParentOfStructFlop(Logic data, Logic valid, {Logic? reset})
      : super(
            name: 'parentStructFlop',
            definitionName: 'ParentOfStructFlop_W${data.width}') {
    if (reset != null) {
      reset = addInput('reset', reset);
    }
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    final s = TwoFieldStruct(dataWidth: data.width, name: 'flopIn');
    s.data <= data;
    s.valid <= valid;

    final sub = StructFlopModule(s, reset: reset);
    final qOut = addOutput('qOut', width: data.width);
    qOut <= sub.qOut;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 9: Multiple sub-modules sharing struct signals
// ─────────────────────────────────────────────────────────────────────────────

/// Parent with two sub-modules both reading the same struct output.
class SharedStructConsumer extends Module {
  Logic get sum => output('sum');
  Logic get xorResult => output('xorResult');

  SharedStructConsumer(Logic data, Logic valid)
      : super(
            name: 'sharedConsumer',
            definitionName: 'SharedStructConsumer_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    // Producer sub-module with struct output
    final producer = StructOutputModule(data, valid);

    // Two consumers reading different fields of the same struct
    final sub1 = StructInputModule(producer.structOut);
    final sub2 = StructGateModule(producer.structOut);

    final sum = addOutput('sum', width: data.width);
    final xorResult = addOutput('xorResult', width: data.width);
    sum <= sub1.dataOut;
    xorResult <= sub2.result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 10: Struct output partially unused (pruning stress test)
// ─────────────────────────────────────────────────────────────────────────────

/// Module with a struct output where only one field is consumed downstream.
class SingleFieldConsumer extends Module {
  Logic get validOnly => output('validOnly');

  SingleFieldConsumer(Logic data, Logic valid)
      : super(
            name: 'singleFieldConsumer',
            definitionName: 'SingleFieldConsumer_W${data.width}') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    final sub = StructOutputModule(data, valid);
    // Only use .valid, ignore .data entirely
    final validOnly = addOutput('validOnly');
    validOnly <= sub.structOut.valid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Case 11-14: Interface patterns that stress pruning + naming
// ─────────────────────────────────────────────────────────────────────────────

/// Sub-module that has BOTH a used output AND an unused struct output.
/// The unused struct output exercises the path where BusSubset slices
/// are created in the parent but the resulting signals are never consumed.
class SubModWithUnusedStructOut extends Module {
  Logic get usedOut => output('usedOut');
  TwoFieldStruct get unusedStructOut =>
      output('unusedStructOut') as TwoFieldStruct;

  SubModWithUnusedStructOut(Logic inp)
      : super(
            name: 'subModUnused', definitionName: 'SubModWithUnusedStructOut') {
    inp = addInput('inp', inp, width: inp.width);

    final usedOut = addOutput('usedOut', width: inp.width);
    usedOut <= inp;

    final structOut = addTypedOutput(
        'unusedStructOut',
        ({name = 'unusedStructOut'}) =>
            TwoFieldStruct(dataWidth: inp.width, name: name));
    structOut.data <= inp;
    structOut.valid <= Const(1);
  }
}

/// Parent that instantiates SubModWithUnusedStructOut but only uses
/// the scalar output, leaving the struct output entirely unconsumed.
class ParentWithUnusedStructOutput extends Module {
  Logic get usedOut => output('usedOut');

  ParentWithUnusedStructOutput(Logic inp)
      : super(
            name: 'parentUnused',
            definitionName: 'ParentWithUnusedStructOutput') {
    inp = addInput('inp', inp, width: inp.width);

    final sub = SubModWithUnusedStructOut(inp);

    // Only consume the scalar output, completely ignore the struct output
    final usedOut = addOutput('usedOut', width: inp.width);
    usedOut <= sub.usedOut;
  }
}

/// Sub-module that outputs a 2-field struct.
class StructProducer extends Module {
  TwoFieldStruct get structOut => output('structOut') as TwoFieldStruct;

  StructProducer(Logic inp)
      : super(name: 'producer', definitionName: 'StructProducer') {
    inp = addInput('inp', inp, width: inp.width);

    final structOut = addTypedOutput(
        'structOut',
        ({name = 'structOut'}) =>
            TwoFieldStruct(dataWidth: inp.width, name: name));
    structOut.data <= inp;
    structOut.valid <= Const(1);
  }
}

/// Parent that only consumes the `data` field of the sub-module's struct
/// output, leaving `valid` unconsumed.
class ParentPartialStructConsumption extends Module {
  Logic get dataOnly => output('dataOnly');

  ParentPartialStructConsumption(Logic inp)
      : super(
            name: 'partialConsume',
            definitionName: 'ParentPartialStructConsumption') {
    inp = addInput('inp', inp, width: inp.width);

    final sub = StructProducer(inp);

    // Only consume .data, leave .valid unused
    final dataOnly = addOutput('dataOnly', width: inp.width);
    dataOnly <= sub.structOut.data;
  }
}

/// Parent that connects sub-module struct output elements to
/// Naming.mergeable locals (which should be merged/pruned).
class MergeableStructConsumer extends Module {
  Logic get result => output('result');

  MergeableStructConsumer(Logic inp)
      : super(
            name: 'mergeableConsumer',
            definitionName: 'MergeableStructConsumer') {
    inp = addInput('inp', inp, width: inp.width);

    final sub = StructProducer(inp);

    // Connect struct output data via a mergeable intermediate
    final intermediate =
        Logic(name: 'tmp', width: inp.width, naming: Naming.mergeable);
    intermediate <= sub.structOut.data;

    final result = addOutput('result', width: inp.width);
    result <= intermediate;
  }
}

/// Simple PairInterface with data+valid ports.
class SimplePairIntf extends PairInterface {
  Logic get data => port('data');
  Logic get valid => port('valid');

  SimplePairIntf({int dataWidth = 8})
      : super(portsFromProvider: [
          Logic.port('data', dataWidth),
          Logic.port('valid'),
        ]);

  @override
  SimplePairIntf clone() => SimplePairIntf(dataWidth: data.width);
}

/// Module using PairInterface that exercises port connection naming.
class PairInterfaceModule extends Module {
  Logic get dataOut => output('dataOut');
  Logic get validOut => output('validOut');

  PairInterfaceModule(Logic data, Logic valid)
      : super(name: 'pairIntfMod', definitionName: 'PairInterfaceModule') {
    data = addInput('data', data, width: data.width);
    valid = addInput('valid', valid);

    // Create a PairInterface and connect as provider
    final intf = SimplePairIntf(dataWidth: data.width);
    intf.data <= data;
    intf.valid <= valid;

    // Sub-module consumes the interface
    final sub = PairIntfConsumer(intf);

    final dataOut = addOutput('dataOut', width: data.width);
    final validOut = addOutput('validOut');
    dataOut <= sub.dataThru;
    validOut <= sub.validThru;
  }
}

/// Sub-module that consumes a PairInterface.
class PairIntfConsumer extends Module {
  Logic get dataThru => output('dataThru');
  Logic get validThru => output('validThru');

  PairIntfConsumer(SimplePairIntf intf)
      : super(name: 'pairConsumer', definitionName: 'PairIntfConsumer') {
    intf = SimplePairIntf(dataWidth: intf.data.width)
      ..pairConnectIO(this, intf, PairRole.consumer);

    final dataThru = addOutput('dataThru', width: intf.data.width);
    final validThru = addOutput('validThru');
    dataThru <= intf.data;
    validThru <= intf.valid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('SystemC generation with LogicStructure ports', () {
    test('Case 1: struct input - generates without assertion failure',
        () async {
      final s = TwoFieldStruct(name: 'inp');
      final mod = StructInputModule(s);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('StructInputModule_W4'));

      // Also verify functional correctness via vectors
      final vectors = [
        // struct packed: [valid(1), data(4)] = 5 bits total
        // valid is MSB, data is lower 4 bits
        Vector({'structIn': 0x1F}, {'dataOut': 0xF, 'validOut': 1}),
        Vector({'structIn': 0x05}, {'dataOut': 0x5, 'validOut': 0}),
        Vector({'structIn': 0x10}, {'dataOut': 0x0, 'validOut': 1}),
        Vector({'structIn': 0x00}, {'dataOut': 0x0, 'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 2: struct output - generates without assertion failure',
        () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = StructOutputModule(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('StructOutputModule_W4'));

      final vectors = [
        Vector({'data': 0xA, 'valid': 1}, {'structOut': 0x1A}),
        Vector({'data': 0x5, 'valid': 0}, {'structOut': 0x05}),
        Vector({'data': 0xF, 'valid': 1}, {'structOut': 0x1F}),
        Vector({'data': 0x0, 'valid': 0}, {'structOut': 0x00}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 3: sub-module struct output consumed by parent', () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = ParentOfStructOutput(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ParentOfStructOutput_W4'));

      final vectors = [
        Vector({'data': 0xA, 'valid': 1}, {'dataOut': 0xA, 'validOut': 1}),
        Vector({'data': 0x5, 'valid': 0}, {'dataOut': 0x5, 'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 4: parent builds struct and feeds to sub-module input',
        () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = ParentOfStructInput(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ParentOfStructInput_W4'));

      final vectors = [
        Vector({'data': 0xC, 'valid': 1}, {'dataOut': 0xC, 'validOut': 1}),
        Vector({'data': 0x3, 'valid': 0}, {'dataOut': 0x3, 'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 5: chained struct passthrough sub-modules', () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = ChainedStructPassthrough(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ChainedStructPassthrough_W4'));

      final vectors = [
        Vector({'data': 0x7, 'valid': 1}, {'dataOut': 0x7}),
        Vector({'data': 0xE, 'valid': 0}, {'dataOut': 0xE}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 6: three-field struct with partial consumption', () async {
      final a = Logic(name: 'a', width: 4);
      final b = Logic(name: 'b', width: 4);
      final c = Logic(name: 'c', width: 4);
      final mod = PartialStructConsumer(a, b, c);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('PartialStructConsumer_W4'));

      // sumOut = a + c (b is unused)
      final vectors = [
        Vector({'a': 1, 'b': 99, 'c': 2}, {'sumOut': 3}),
        Vector({'a': 5, 'b': 0, 'c': 3}, {'sumOut': 8}),
        Vector({'a': 0xF, 'b': 7, 'c': 1}, {'sumOut': 0}), // overflow wraps
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 7: struct input with gate operations on fields', () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = ParentOfStructGate(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ParentOfStructGate_W4'));

      // result = mux(valid, data, 0)
      final vectors = [
        Vector({'data': 0xA, 'valid': 1}, {'result': 0xA}),
        Vector({'data': 0xA, 'valid': 0}, {'result': 0x0}),
        Vector({'data': 0xF, 'valid': 1}, {'result': 0xF}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 8: struct input with sequential logic (flop)', () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final reset = Logic(name: 'reset');
      final mod = ParentOfStructFlop(data, valid, reset: reset);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ParentOfStructFlop_W4'));

      // Flop with enable: qOut follows data when valid=1
      // Clock is internal (SimpleClockGenerator), not in vectors
      final vectors = [
        Vector({'data': 0, 'valid': 0, 'reset': 1}, {}),
        Vector({'data': 0xA, 'valid': 1, 'reset': 0}, {'qOut': 0}),
        Vector({'data': 0xB, 'valid': 1, 'reset': 0}, {'qOut': 0xA}),
        Vector({'data': 0xC, 'valid': 0, 'reset': 0}, {'qOut': 0xB}),
        Vector({'data': 0xD, 'valid': 0, 'reset': 0}, {'qOut': 0xB}),
        Vector({'data': 0xE, 'valid': 1, 'reset': 0}, {'qOut': 0xB}),
        Vector({'data': 0xF, 'valid': 1, 'reset': 0}, {'qOut': 0xE}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      // Note: SystemC check skipped — SimpleClockGenerator inside a sub-module
      // causes unbound clk port, unrelated to struct naming.
    });

    test('Case 9: multiple sub-modules sharing one struct output', () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = SharedStructConsumer(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('SharedStructConsumer_W4'));

      // sum = data (passthrough via StructInputModule)
      // xorResult = mux(valid, data, 0) (via StructGateModule)
      final vectors = [
        Vector({'data': 0xA, 'valid': 1}, {'sum': 0xA, 'xorResult': 0xA}),
        Vector({'data': 0xA, 'valid': 0}, {'sum': 0xA, 'xorResult': 0x0}),
        Vector({'data': 0x5, 'valid': 1}, {'sum': 0x5, 'xorResult': 0x5}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 10: struct output with only one field consumed (pruning stress)',
        () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final mod = SingleFieldConsumer(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('SingleFieldConsumer_W4'));

      // Only .valid is consumed; .data should be prunable
      final vectors = [
        Vector({'data': 0xF, 'valid': 1}, {'validOnly': 1}),
        Vector({'data': 0xF, 'valid': 0}, {'validOnly': 0}),
        Vector({'data': 0x0, 'valid': 1}, {'validOnly': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 3 - build-only: struct output sub-module generateSynth',
        () async {
      final data = Logic(name: 'data', width: 8);
      final valid = Logic(name: 'valid');
      final mod = ParentOfStructOutput(data, valid);
      await mod.build();

      // Just verify it doesn't throw during SystemC generation
      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });

    test('Case 5 - build-only: chained struct passthrough generateSynth',
        () async {
      final data = Logic(name: 'data', width: 8);
      final valid = Logic(name: 'valid');
      final mod = ChainedStructPassthrough(data, valid);
      await mod.build();

      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });

    test('Case 6 - build-only: partial struct consumer generateSynth',
        () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final c = Logic(name: 'c', width: 8);
      final mod = PartialStructConsumer(a, b, c);
      await mod.build();

      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });

    test('Case 10 - build-only: single field consumer generateSynth', () async {
      final data = Logic(name: 'data', width: 8);
      final valid = Logic(name: 'valid');
      final mod = SingleFieldConsumer(data, valid);
      await mod.build();

      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Interface/PairInterface patterns that stress pruning + naming
  // ─────────────────────────────────────────────────────────────────────────
  group('SystemC generation with Interface struct patterns', () {
    test('Case 11: sub-module with unused struct output (pruning path)',
        () async {
      // Pattern from TopWithUnusedSubModPorts: sub-module has a struct output
      // that the parent doesn't consume. The struct output's leaf elements
      // should be prunable without causing naming assertions.
      final inp = Logic(name: 'inp', width: 8);
      final mod = ParentWithUnusedStructOutput(inp);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ParentWithUnusedStructOutput'));
      // Should NOT assert on signal naming

      final vectors = [
        Vector({'inp': 0xAB}, {'usedOut': 0xAB}),
        Vector({'inp': 0xCD}, {'usedOut': 0xCD}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test(
        'Case 12: sub-module struct output partially consumed (pruning stress)',
        () async {
      // Sub-module outputs a struct, parent only uses one field.
      // The unused field's BusSubset slice should be properly handled.
      final inp = Logic(name: 'inp', width: 8);
      final mod = ParentPartialStructConsumption(inp);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('ParentPartialStructConsumption'));

      final vectors = [
        Vector({'inp': 0xAB}, {'dataOnly': 0xAB}),
        Vector({'inp': 0x12}, {'dataOnly': 0x12}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 13: mergeable signals connected to struct output elements',
        () async {
      // Tests that when a struct output element is connected to a
      // Naming.mergeable local, the merged signal still gets a name.
      final inp = Logic(name: 'inp', width: 8);
      final mod = MergeableStructConsumer(inp);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('MergeableStructConsumer'));

      final vectors = [
        Vector({'inp': 0x55}, {'result': 0x55}),
        Vector({'inp': 0xFF}, {'result': 0xFF}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 14: PairInterface with struct-like multi-port pattern',
        () async {
      // Exercises the PairInterface pattern where multiple ports form a
      // logical struct-like group, stressing the naming system.
      final data = Logic(name: 'data', width: 8);
      final valid = Logic(name: 'valid');
      final mod = PairInterfaceModule(data, valid);
      await mod.build();

      final sc = mod.generateSynth();
      expect(sc, contains('PairInterfaceModule'));

      final vectors = [
        Vector({'data': 0xAA, 'valid': 1}, {'dataOut': 0xAA, 'validOut': 1}),
        Vector({'data': 0x55, 'valid': 0}, {'dataOut': 0x55, 'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('Case 11 - build-only: unused struct output generateSynth', () async {
      final inp = Logic(name: 'inp', width: 8);
      final mod = ParentWithUnusedStructOutput(inp);
      await mod.build();
      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });

    test('Case 12 - build-only: partial struct consumption generateSynth',
        () async {
      final inp = Logic(name: 'inp', width: 8);
      final mod = ParentPartialStructConsumption(inp);
      await mod.build();
      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });

    test('Case 13 - build-only: mergeable struct consumer generateSynth',
        () async {
      final inp = Logic(name: 'inp', width: 8);
      final mod = MergeableStructConsumer(inp);
      await mod.build();
      SimCompare.checkSystemCVector(mod, [], buildOnly: true);
    });
  });
}

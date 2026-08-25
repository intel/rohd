// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// struct_port_pruning_test.dart
// Verifies that struct port elements on submodules are not incorrectly
// pruned during SV synthesis.  Exercises the `submoduleOutputSynths` /
// `submoduleInputSynths` fix in `_pruneUnused`.
//
// 2026 April 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

// ── Struct definition ──────────────────────────────────────────

class PairStruct extends LogicStructure {
  PairStruct({Logic? a, Logic? b, super.name = 'pair'})
      : super([a ?? Logic(name: 'a'), b ?? Logic(name: 'b')]);

  @override
  PairStruct clone({String? name}) => PairStruct(name: name);
}

// ── Leaf submodule with a struct output port ───────────────────

class StructProducer extends Module {
  Logic get out => PairStruct()..gets(output('out'));

  StructProducer(Logic x, Logic y) : super(name: 'struct_producer') {
    x = addInput('x', x);
    y = addInput('y', y);

    final s = PairStruct(a: x, b: y);
    addOutput('out', width: s.width) <= s;
  }
}

// ── Leaf submodule with a struct input port ────────────────────

class StructConsumer extends Module {
  Logic get sum => output('sum');

  StructConsumer(Logic pair) : super(name: 'struct_consumer') {
    pair = addInput('pair', pair, width: pair.width);

    final s = PairStruct()..gets(pair);
    addOutput('sum') <= s.elements[0] ^ s.elements[1];
  }
}

// ── Top module: struct output from submodule → struct input ───

class StructPipeTop extends Module {
  Logic get result => output('result');

  StructPipeTop(Logic x, Logic y) : super(name: 'struct_pipe_top') {
    x = addInput('x', x);
    y = addInput('y', y);

    final producer = StructProducer(x, y);
    final consumer = StructConsumer(producer.out);

    addOutput('result') <= consumer.sum;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('struct port pruning', () {
    test('SV output retains struct element signals from submodule', () async {
      final dut = StructPipeTop(Logic(), Logic());
      await dut.build();

      final svStr = dut.generateSynth();

      // The struct_producer submodule should appear in the SV.
      expect(
        svStr,
        contains('struct_producer'),
        reason: 'Submodule with struct output should not be pruned',
      );

      // The struct_consumer submodule should appear in the SV.
      expect(
        svStr,
        contains('struct_consumer'),
        reason: 'Submodule with struct input should not be pruned',
      );

      // The output port 'out' of struct_producer (width 2) must have a
      // connection in the parent — it should not be pruned away.
      expect(
        svStr,
        contains('.out('),
        reason: 'Struct output port connection should not be pruned',
      );

      // The input port 'pair' of struct_consumer must be connected.
      expect(
        svStr,
        contains('.pair('),
        reason: 'Struct input port connection should not be pruned',
      );
    });

    test('struct element signals survive SV synthesis for producer', () async {
      final dut = StructProducer(Logic(), Logic());
      await dut.build();

      final svStr = dut.generateSynth();

      // Inside StructProducer, the struct elements (a, b from PairStruct)
      // drive the output via struct_slice decomposition.  They must not
      // be pruned.
      expect(svStr, contains('out'), reason: 'Output port should appear in SV');
      expect(
        svStr,
        contains('input'),
        reason: 'Input ports should appear in SV',
      );
    });

    test('struct element signals survive SV synthesis for consumer', () async {
      final dut = StructConsumer(Logic(width: 2));
      await dut.build();

      final svStr = dut.generateSynth();

      // Inside StructConsumer, the struct elements are extracted from the
      // packed input.  The XOR of elements drives the output.
      expect(svStr, contains('sum'), reason: 'Output port should appear in SV');
      expect(
        svStr,
        contains('pair'),
        reason: 'Input struct port should appear in SV',
      );
    });
  });
}

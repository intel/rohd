// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// submodule_output_aggregate_test.dart
// Preserves aggregate child outputs without losing meaningful signal names.
//
// 2026 October 19
// Author: ROHD Contributors

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _Transmitter extends Module {
  _Transmitter(Logic data) : super(name: 'transmitter') {
    data = addInput('data', data, width: data.width);
    addOutput('dataOut', width: data.width) <= data;
  }
}

class _Receiver extends Module {
  _Receiver(Logic data, {required super.name}) {
    data = addInput('dataIn', data);
    addOutput('received') <= data;
  }
}

class _SplitReceivers extends Module {
  _SplitReceivers({Naming? aliasNaming, bool collision = false}) {
    final data = addInput('data', Logic(width: 2), width: 2);
    final transmitter = _Transmitter(data);
    var transmitted = transmitter.output('dataOut');
    if (aliasNaming != null) {
      transmitted = Logic(width: 2, name: 'link', naming: aliasNaming)
        ..gets(transmitted);
    }
    for (var bit = 0; bit < 2; bit++) {
      final receiver = _Receiver(transmitted[bit],
          name: collision && bit == 0 ? 'dataOut' : 'receiver_$bit');
      addOutput('received$bit') <= receiver.output('received');
    }
  }
}

class _Pair extends LogicStructure {
  final Logic low;
  final Logic high;

  factory _Pair({String name = 'pair'}) => _Pair._(
        Logic(name: 'low'),
        Logic(name: 'high'),
        name: name,
      );

  _Pair._(this.low, this.high, {required super.name}) : super([low, high]);

  @override
  _Pair clone({String? name}) => _Pair(name: name ?? this.name);
}

class _StructureTransmitter extends Module {
  _StructureTransmitter(Logic data) {
    data = addInput('data', data, width: 2);
    final dataOut = addTypedOutput('dataOut', _Pair.new);
    dataOut.low <= data[0];
    dataOut.high <= data[1];
  }
}

class _StructureReceivers extends Module {
  _StructureReceivers() {
    final data = addInput('data', Logic(width: 2), width: 2);
    final transmitter = _StructureTransmitter(data);
    final transmitted = transmitter.output('dataOut') as _Pair;
    final low = _Receiver(transmitted.low, name: 'receiver_0');
    final high = _Receiver(transmitted.high, name: 'receiver_1');
    addOutput('received0') <= low.output('received');
    addOutput('received1') <= high.output('received');
  }
}

class _StructureDestination extends Module {
  _StructureDestination() {
    final data = addInput('data', Logic(width: 2), width: 2);
    final transmitted = _Transmitter(data).output('dataOut');
    final pair = addTypedOutput('pair', _Pair.new);
    pair.low <= transmitted[0];
    pair.high <= transmitted[1];
  }
}

class _Harness extends Module {
  _Harness(Module child) {
    final data = addInput('data', Logic(width: 2), width: 2);
    child.inputSource('data') <= data;
    for (final entry in child.outputs.entries) {
      addOutput(entry.key, width: entry.value.width) <= entry.value;
    }
  }
}

String _topBody(Module module) {
  final sv = module.dumpSystemVerilog();
  return sv.substring(RegExp(r'(?:^|\n)module ').allMatches(sv).last.start);
}

List<Vector> _receiverVectors() => [
      for (final text in ['00', '01', '10', '11', 'xz', 'zx'])
        Vector({
          'data': LogicValue.ofString(text)
        }, {
          'received0': LogicValue.ofString(text[1]),
          'received1': LogicValue.ofString(text[0]),
        }),
    ];

void main() {
  tearDown(Simulator.reset);

  for (final configuration in [
    (naming: null, collision: false, expected: 'dataOut'),
    (naming: null, collision: true, expected: 'dataOut_0'),
    (naming: Naming.renameable, collision: false, expected: 'link'),
    (naming: Naming.reserved, collision: false, expected: 'link'),
  ]) {
    // Check naming, bit order, repeated synthesis and nested composition.
    test('retains producer bus for split receivers $configuration', () async {
      final module = _SplitReceivers(
          aliasNaming: configuration.naming,
          collision: configuration.collision);
      await module.build();
      final body = _topBody(module);
      final name = configuration.expected;
      expect(body, contains('logic [1:0] $name;'), reason: body);
      expect(body, contains('.dataOut($name)'), reason: body);
      expect(body, isNot(contains('.dataOut({')), reason: body);
      NetlistSynthesizer().synthesizeToJson(module);
      expect(_topBody(module), body);
      final vectors = _receiverVectors();
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);

      final harness = _Harness(_SplitReceivers(
          aliasNaming: configuration.naming,
          collision: configuration.collision));
      await harness.build();
      expect(harness.dumpSystemVerilog(), contains('.dataOut($name)'));
    });
  }

  // A typed output must stay whole even when every field has a scalar consumer.
  test('retains typed producer output for field receivers', () async {
    final module = _StructureReceivers();
    await module.build();
    final body = _topBody(module);
    expect(body, contains('.dataOut(dataOut)'), reason: body);
    expect(body, isNot(contains('.dataOut({')), reason: body);
    NetlistSynthesizer().synthesizeToJson(module);
    expect(_topBody(module), body);
    final vectors = _receiverVectors();
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
    await _Harness(_StructureReceivers()).build();
  });

  // Do not replace a packed producer by the leaves of a destination structure.
  test('retains producer bus at a structured conversion boundary', () async {
    final module = _StructureDestination();
    await module.build();
    final body = _topBody(module);
    expect(body, isNot(contains('.dataOut({')), reason: body);
    expect(body, contains('.dataOut(dataOut)'), reason: body);
    final vectors = [
      for (final text in ['00', '01', '10', '11', 'xz', 'zx'])
        Vector({'data': LogicValue.ofString(text)},
            {'pair': LogicValue.ofString(text)}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
    await _Harness(_StructureDestination()).build();
  });
}

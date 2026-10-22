// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum _State { idle, busy, done }

LogicEnum<_State> _state({String? name}) =>
    LogicEnum(_State.values, name: name);

class _EnumRecord extends LogicStructure {
  LogicEnum<_State> get state => elements[0] as LogicEnum<_State>;

  _EnumRecord({String? name})
      : super([_state(name: 'state')], name: name ?? 'record');

  @override
  _EnumRecord clone({String? name}) => _EnumRecord(name: name ?? this.name);
}

class _EnumArrayRead extends Module {
  _EnumArrayRead(List<int> dimensions) {
    final source = addTypedInput('source',
        TypedLogicArray<LogicEnum<_State>, LogicValue>(dimensions, _state));
    final result = addTypedOutput<LogicEnum<_State>>('result', _state);
    Combinational([
      result < source.at(List.filled(dimensions.length, 0)),
    ]);
  }
}

class _EnumFieldRead extends Module {
  _EnumFieldRead(List<int> dimensions) {
    final source = addTypedInput('source',
        TypedLogicArray<_EnumRecord, LogicValue>(dimensions, _EnumRecord.new));
    final result = addTypedOutput<LogicEnum<_State>>('result', _state);
    Combinational([
      result < source.at(List.filled(dimensions.length, 0)).state,
    ]);
  }
}

void main() {
  tearDown(Simulator.reset);

  for (final dimensions in [
    <int>[],
    [3],
    [2, 2]
  ]) {
    // Enum leaves have packed array declarations, so procedural reads must
    // convert the selected packed bits back into the destination enum.
    for (final field in [false, true]) {
      test('procedural enum read from array $dimensions field=$field',
          () async {
        final dut =
            field ? _EnumFieldRead(dimensions) : _EnumArrayRead(dimensions);
        await dut.build();
        final vectors = [
          Vector({'source': 0}, {'result': 0}),
          Vector({'source': 1}, {'result': 1}),
          Vector({'source': 2}, {'result': 2}),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, vectors);
      });
    }
  }
}

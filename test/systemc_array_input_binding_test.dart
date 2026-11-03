// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_array_input_binding_test.dart
// Tests SystemC bindings for direct array-element submodule inputs.
//
// 2026 October 27
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _ArrayInputLeaf extends Module {
  Logic get y => output('y');

  _ArrayInputLeaf(Logic a, {required super.name})
      : super(definitionName: 'ArrayInputLeaf_W${a.width}') {
    a = addInput('a', a, width: a.width);
    addOutput('y', width: a.width) <= a;
  }
}

class _ArrayElementInputParent extends Module {
  _ArrayElementInputParent(LogicArray values)
      : super(definitionName: 'ArrayElementInputParent') {
    values = addInputArray(
      'values',
      values,
      dimensions: values.dimensions,
      elementWidth: values.elementWidth,
    );
    final low = _ArrayInputLeaf(values.elements[0], name: 'low');
    final high = _ArrayInputLeaf(values.elements[1], name: 'high');
    addOutput('observed', width: values.width) <= [high.y, low.y].swizzle();
  }
}

class _ArrayElementOutputParent extends Module {
  _ArrayElementOutputParent(Logic lowValue, Logic highValue)
      : super(definitionName: 'ArrayElementOutputParent') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final values = addOutputArray('values', dimensions: [2], elementWidth: 8);
    final low = _ArrayInputLeaf(lowValue, name: 'low');
    final high = _ArrayInputLeaf(highValue, name: 'high');
    values.elements[0] <= low.y;
    values.elements[1] <= high.y;
  }
}

class _ArrayInputConsumer extends Module {
  Logic get observed => output('observed');

  _ArrayInputConsumer(LogicArray values, {required super.name})
      : super(definitionName: 'ArrayInputConsumer_W${values.width}') {
    values = addInputArray(
      'values',
      values,
      dimensions: values.dimensions,
      elementWidth: values.elementWidth,
    );
    addOutput('observed', width: values.width) <= values;
  }
}

class _ElementInputsToArrayChildParent extends Module {
  _ElementInputsToArrayChildParent(Logic lowValue, Logic highValue)
      : super(definitionName: 'ElementInputsToArrayChildParent') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final values = LogicArray([2], 8, name: 'values');
    values.elements[0] <= lowValue;
    values.elements[1] <= highValue;
    final child = _ArrayInputConsumer(values, name: 'consumer');
    addOutput('observed', width: values.width) <= child.observed;
  }
}

class _ArrayOutputProducer extends Module {
  LogicArray get values => output('values') as LogicArray;

  _ArrayOutputProducer(Logic lowValue, Logic highValue, {required super.name})
      : super(definitionName: 'ArrayOutputProducer_W${lowValue.width * 2}') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final values = addOutputArray('values', dimensions: [2], elementWidth: 8);
    values.elements[0] <= lowValue;
    values.elements[1] <= highValue;
  }
}

class _ArrayChildOutputToParentParent extends Module {
  _ArrayChildOutputToParentParent(Logic lowValue, Logic highValue)
      : super(definitionName: 'ArrayChildOutputToParentParent') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final source = _ArrayOutputProducer(lowValue, highValue, name: 'source');
    final values = addOutputArray('values', dimensions: [2], elementWidth: 8);
    values <= source.values;
  }
}

class _PackedPair extends LogicStructure {
  Logic get low => elements[0];
  Logic get high => elements[1];

  _PackedPair({String? name})
      : super([
          Logic(name: 'low', width: 4),
          Logic(name: 'high', width: 4),
        ], name: name ?? 'packed_pair');

  @override
  _PackedPair clone({String? name}) => _PackedPair(name: name ?? this.name);
}

class _StructureInputConsumer extends Module {
  Logic get observed => output('observed');

  _StructureInputConsumer(_PackedPair pair, {required super.name})
      : super(definitionName: 'StructureInputConsumer') {
    pair = addTypedInput('pair', pair);
    addOutput('observed', width: pair.width) <= pair;
  }
}

class _ScalarInputsToStructureChild extends Module {
  _ScalarInputsToStructureChild(Logic lowValue, Logic highValue)
      : super(definitionName: 'ScalarInputsToStructureChild') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final pair = _PackedPair(name: 'pair');
    pair.low <= lowValue;
    pair.high <= highValue;
    final child = _StructureInputConsumer(pair, name: 'consumer');
    addOutput('observed', width: pair.width) <= child.observed;
  }
}

class _StructureOutputProducer extends Module {
  _PackedPair get pair => output('pair') as _PackedPair;

  _StructureOutputProducer(
    Logic lowValue,
    Logic highValue, {
    required super.name,
  }) : super(definitionName: 'StructureOutputProducer') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final value = _PackedPair(name: 'pairValue');
    value.low <= lowValue;
    value.high <= highValue;
    addTypedOutput('pair', value.clone).gets(value);
  }
}

class _StructureChildToParentOutput extends Module {
  _StructureChildToParentOutput(Logic lowValue, Logic highValue)
      : super(definitionName: 'StructureChildToParentOutput') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final child = _StructureOutputProducer(lowValue, highValue, name: 'source');
    addTypedOutput('pair', child.pair.clone).gets(child.pair);
  }
}

class _ArrayElementRecord extends LogicStructure {
  Logic get data => elements.single;

  _ArrayElementRecord({String? name})
      : super([Logic(name: 'data', width: 8)],
            name: name ?? 'array_element_record');

  @override
  _ArrayElementRecord clone({String? name}) =>
      _ArrayElementRecord(name: name ?? this.name);
}

class _StructuredArrayElementInputParent extends Module {
  _StructuredArrayElementInputParent()
      : super(definitionName: 'StructuredArrayElementInputParent') {
    final values = addTypedInput(
      'values',
      TypedLogicArray<_ArrayElementRecord, LogicValue>(
        [2],
        _ArrayElementRecord.new,
        name: 'values',
      ),
    );
    final low = _ArrayInputLeaf(values.at([0]).data, name: 'low');
    final high = _ArrayInputLeaf(values.at([1]).data, name: 'high');
    addOutput('observed', width: values.width) <= [high.y, low.y].swizzle();
  }
}

class _NestedArrayElementInputParent extends Module {
  _NestedArrayElementInputParent(LogicArray values)
      : super(definitionName: 'NestedArrayElementInputParent') {
    values = addInputArray(
      'values',
      values,
      dimensions: values.dimensions,
      elementWidth: values.elementWidth,
    );
    final low = _ArrayInputLeaf(values.elements[0].elements[1], name: 'low');
    final high = _ArrayInputLeaf(values.elements[1].elements[0], name: 'high');
    addOutput('observed', width: 16) <= [high.y, low.y].swizzle();
  }
}

class _PackedSelectionInputParent extends Module {
  _PackedSelectionInputParent(Logic data)
      : super(definitionName: 'PackedSelectionInputParent') {
    data = addInput('data', data, width: 16);
    final low = _ArrayInputLeaf(data.getRange(0, 8), name: 'low');
    final high = _ArrayInputLeaf(data.getRange(8, 16), name: 'high');
    final msb = _ArrayInputLeaf(data.getRange(15, 16), name: 'msb');
    addOutput('observed', width: data.width) <= [high.y, low.y].swizzle();
    addOutput('observedMsb') <= msb.y;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  tearDownAll(SimCompare.cleanupSystemCCache);

  test('direct LogicArray elements bind through declared SystemC bridges',
      () async {
    final dut = _ArrayElementInputParent(LogicArray([2], 8, name: 'values'));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(
      systemC,
      contains(
        'sc_signal<sc_uint<8>> rohd_input_bridge_0{"rohd_input_bridge_0"};',
      ),
    );
    expect(
      systemC,
      contains(
        'rohd_input_bridge_0 = '
        'sc_uint<8>(values.read().range(7, 0));',
      ),
    );
    expect(
      systemC,
      contains(
        'rohd_input_bridge_1 = '
        'sc_uint<8>(values.read().range(15, 8));',
      ),
    );
    expect(systemC, contains('low.a(rohd_input_bridge_0);'));
    expect(systemC, contains('high.a(rohd_input_bridge_1);'));

    SimCompare.checkSystemCVector(dut, [
      Vector({'values': 0xa55a}, {'observed': 0xa55a}),
    ]);
  });

  test('direct packed selections retain bindable SystemC paths', () async {
    final dut = _PackedSelectionInputParent(Logic(width: 16));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(systemC, contains('SC_MODULE(PackedSelectionInputParent)'));

    SimCompare.checkSystemCVector(dut, [
      Vector(
        {'data': 0xa55a},
        {'observed': 0xa55a, 'observedMsb': 1},
      ),
    ]);
  });

  test('direct child outputs pack into flattened SystemC array ports',
      () async {
    final dut = _ArrayElementOutputParent(Logic(width: 8), Logic(width: 8));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(
      systemC,
      contains('sc_signal<sc_uint<8>> values_0_{"values_0_"};'),
    );
    expect(
      systemC,
      contains('sc_signal<sc_uint<8>> values_1_{"values_1_"};'),
    );
    expect(systemC, contains('low.y(values_0_);'));
    expect(systemC, contains('high.y(values_1_);'));
    expect(
      systemC,
      contains('values = (values_1_.read(), values_0_.read());'),
    );

    SimCompare.checkSystemCVector(dut, [
      Vector(
        {'lowValue': 0x5a, 'highValue': 0xa5},
        {'values': 0xa55a},
      ),
    ]);
  });

  test('scalar elements pack before an aggregate SystemC child input',
      () async {
    final dut =
        _ElementInputsToArrayChildParent(Logic(width: 8), Logic(width: 8));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(systemC, contains('consumer.values(values);'));
    expect(
      systemC,
      contains('values = (values_1_.read(), values_0_.read());'),
    );

    SimCompare.checkSystemCVector(dut, [
      Vector(
        {'lowValue': 0x5a, 'highValue': 0xa5},
        {'observed': 0xa55a},
      ),
    ]);
  });

  test('aggregate child outputs remain packed through parent SystemC outputs',
      () async {
    final dut =
        _ArrayChildOutputToParentParent(Logic(width: 8), Logic(width: 8));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(systemC, contains('source.values(values);'));
    expect(
      systemC,
      contains('values = (values_1_.read(), values_0_.read());'),
    );

    SimCompare.checkSystemCVector(dut, [
      Vector(
        {'lowValue': 0x5a, 'highValue': 0xa5},
        {'values': 0xa55a},
      ),
    ]);
  });

  test('structure fields pack into aggregate SystemC child inputs', () async {
    final dut = _ScalarInputsToStructureChild(Logic(width: 4), Logic(width: 4));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(systemC, contains('consumer.pair(pair);'));

    SimCompare.checkSystemCVector(dut, [
      Vector(
        {'lowValue': 0x5, 'highValue': 0xa},
        {'observed': 0xa5},
      ),
    ]);
  });

  test('aggregate structure child outputs pack through SystemC parents',
      () async {
    final dut = _StructureChildToParentOutput(Logic(width: 4), Logic(width: 4));
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(systemC, contains('source.pair(pair_0);'));
    expect(
      systemC,
      contains(
        'pair = sc_uint<8>(pair_low.read()) | '
        '(sc_uint<8>(pair_high.read()) << 4);',
      ),
    );

    SimCompare.checkSystemCVector(dut, [
      Vector(
        {'lowValue': 0x5, 'highValue': 0xa},
        {'pair': 0xa5},
      ),
    ]);
  });

  test('nested LogicArray elements use flattened SystemC bridge ranges',
      () async {
    final dut = _NestedArrayElementInputParent(
      LogicArray([2, 2], 8, name: 'values'),
    );
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(
      systemC,
      contains(
        'rohd_input_bridge_0 = '
        'sc_uint<8>(values.read().range(15, 8));',
      ),
    );
    expect(
      systemC,
      contains(
        'rohd_input_bridge_1 = '
        'sc_uint<8>(values.read().range(23, 16));',
      ),
    );

    SimCompare.checkSystemCVector(dut, [
      Vector({'values': 0xabcd1234}, {'observed': 0xcd12}),
    ]);
  });

  test('direct structured-array fields bind through SystemC bridges', () async {
    final dut = _StructuredArrayElementInputParent();
    await dut.build();

    final systemC = SystemCService(dut, register: false).output;
    expect(
      systemC,
      contains(
        'rohd_input_bridge_0 = '
        'sc_uint<8>(values.read().range(7, 0));',
      ),
    );
    expect(
      systemC,
      contains(
        'rohd_input_bridge_1 = '
        'sc_uint<8>(values.read().range(15, 8));',
      ),
    );

    SimCompare.checkSystemCVector(dut, [
      Vector({'values': 0xa55a}, {'observed': 0xa55a}),
    ]);
  });
}

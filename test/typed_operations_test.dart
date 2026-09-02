// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_operations_test.dart
// Tests operations that preserve concrete LogicStructure types.
//
// 2026 September 2
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _TypedLane extends LogicStructure {
  Logic get data => elements[0];
  Logic get enable => elements[1];

  _TypedLane({String? name})
      : super([
          Logic(name: 'data', width: 8),
          Logic(name: 'enable'),
        ], name: name ?? 'typed_lane');

  @override
  _TypedLane clone({String? name}) => _TypedLane(name: name ?? this.name);
}

class _TypedPacket extends LogicStructure {
  Logic get opcode => elements[0];
  LogicArrayOf<_TypedLane> get lanes => elements[1] as LogicArrayOf<_TypedLane>;

  final List<int> laneDimensions;

  _TypedPacket({this.laneDimensions = const [2], String? name})
      : super([
          Logic(name: 'opcode', width: 3),
          LogicArrayOf<_TypedLane>(laneDimensions, _TypedLane.new,
              name: 'lanes'),
        ], name: name ?? 'typed_packet');

  @override
  _TypedPacket clone({String? name}) =>
      _TypedPacket(laneDimensions: laneDimensions, name: name ?? this.name);
}

class _BadClonePacket extends LogicStructure {
  _BadClonePacket({String? name})
      : super([Logic(name: 'data')], name: name ?? 'bad_clone_packet');

  @override
  LogicStructure clone({String? name}) =>
      LogicStructure([Logic(name: 'data')], name: name ?? this.name);
}

class _ConstPacket extends LogicStructure {
  _ConstPacket({String? name})
      : super([Const(1)], name: name ?? 'const_packet');

  @override
  _ConstPacket clone({String? name}) => _ConstPacket(name: name ?? this.name);
}

class _NetPacket extends LogicStructure {
  _NetPacket({String? name}) : super([LogicNet()], name: name ?? 'net_packet');

  @override
  _NetPacket clone({String? name}) => _NetPacket(name: name ?? this.name);
}

class _TypedOperationsSynthesisHarness extends Module {
  _TypedOperationsSynthesisHarness(Logic clk, Logic reset, Logic control,
      Logic selector, _TypedPacket first, _TypedPacket second) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    control = addInput('control', control);
    selector = addInput('selector', selector, width: selector.width);
    first = addTypedInput('first', first);
    second = addTypedInput('second', second);

    final selected = Mux(control, second, first).out;
    final selectedByCase = typedCases(
      selector,
      {0: first, 1: second},
      defaultValue: selected,
      name: 'selected_by_case',
    );
    final selectedByIndex = [first, second, selectedByCase].selectIndexTyped(
      selector,
      defaultValue: first,
      name: 'selected_by_index',
    );
    final passed = Passthrough(selectedByIndex).out;
    final registered = FlipFlop(
      clk,
      passed,
      reset: reset,
      resetValue: 0,
    ).q;
    final piped = StructurePipeline<_TypedPacket>(
      clk,
      registered,
      reset: reset,
      resetValue: 0,
      stages: [
        (stage) => stage.value.namedTyped('pipeline_stage_value'),
      ],
    ).output;
    addTypedOutput('out', piped.clone).gets(piped);
  }
}

void _expectLogicArray(LogicArray array) {
  expect(array, isA<LogicArray>());
}

void _expectTypedLaneArray(LogicArrayOf<_TypedLane> array) {
  expect(array, isA<LogicArrayOf<_TypedLane>>());
}

void main() {
  tearDown(Simulator.reset);

  test('Mux implements the scalar TypedOp contract', () {
    final muxModule = Mux(Logic(), Logic(width: 4), Logic(width: 4));
    expect(muxModule, isA<TypedOp<Logic>>());
    expect(muxModule.out.runtimeType, Logic);
  });

  test('scalar typed operations normalize constants, ports, and nets',
      () async {
    final clk = SimpleClockGenerator(10).clk;
    final control = Logic();
    final ordinary = Logic(width: 4);
    final constant = Const(0xa, width: 4);
    final portPrototype = Logic.port('port_data', 4);
    final netDriver = Logic(width: 4);
    final net = LogicNet(width: 4)..gets(netDriver);
    final constantMux = Mux<Logic>(control, constant, ordinary);
    final portMux = Mux<Logic>(control, portPrototype, ordinary);
    final netMux = Mux<Logic>(control, net, ordinary);
    final constantFlop = FlipFlop<Logic>(clk, constant);
    final portFlop = FlipFlop<Logic>(clk, portPrototype);
    final netFlop = FlipFlop<Logic>(clk, net);
    await Future.wait([
      constantMux.build(),
      portMux.build(),
      netMux.build(),
      constantFlop.build(),
      portFlop.build(),
      netFlop.build(),
    ]);
    unawaited(Simulator.run());

    for (final output in [
      constantMux.out,
      portMux.out,
      netMux.out,
      constantFlop.q,
      portFlop.q,
      netFlop.q,
    ]) {
      expect(output.runtimeType, Logic);
      expect(output.isNet, isFalse);
    }

    ordinary.inject(3);
    portPrototype.inject(5);
    netDriver.inject(7);
    control.inject(1);
    await Simulator.tick();
    expect(constantMux.out.value.toInt(), 0xa);
    expect(portMux.out.value.toInt(), 5);
    expect(netMux.out.value.toInt(), 7);
    await clk.nextPosedge;
    expect(constantFlop.q.value.toInt(), 0xa);
    expect(portFlop.q.value.toInt(), 5);
    expect(netFlop.q.value.toInt(), 7);
    await Simulator.endSimulation();
  });

  test('typed operations infer top-level array types', () {
    final clk = Logic();
    final selector = Logic(width: 2);
    final array0 = LogicArray([2], 4, name: 'array0');
    final array1 = LogicArray([2], 4, name: 'array1');
    final typedArray0 =
        LogicArrayOf<_TypedLane>([2], _TypedLane.new, name: 'typed_array0');
    final typedArray1 =
        LogicArrayOf<_TypedLane>([2], _TypedLane.new, name: 'typed_array1');

    final muxedArray = Mux(selector[0], array1, array0).out;
    final floppedArray = FlipFlop(clk, array0).q;
    final passedArray = Passthrough(array0).out;
    final casedArray = typedCases(selector, {0: array0, 1: array1});
    final selectedArray = [array0, array1].selectIndexTyped(selector);
    final selectedFromArray = selector.selectFromTyped([array0, array1]);
    final clonedArray = array0.cloneTyped();
    final namedArray = array0.namedTyped('named_array');
    final pipelinedArray = StructurePipeline<LogicArray>(
      clk,
      array0,
      stages: [(stage) => stage.value],
    ).output;

    final muxedTypedArray = Mux(selector[0], typedArray1, typedArray0).out;
    final floppedTypedArray = FlipFlop(clk, typedArray0).q;
    final passedTypedArray = Passthrough(typedArray0).out;
    final casedTypedArray =
        typedCases(selector, {0: typedArray0, 1: typedArray1});
    final selectedTypedArray =
        [typedArray0, typedArray1].selectIndexTyped(selector);
    final selectedFromTypedArray =
        selector.selectFromTyped([typedArray0, typedArray1]);
    final clonedTypedArray = typedArray0.cloneTyped();
    final namedTypedArray = typedArray0.namedTyped('named_typed_array');
    final pipelinedTypedArray = StructurePipeline<LogicArrayOf<_TypedLane>>(
      clk,
      typedArray0,
      stages: [(stage) => stage.value],
    ).output;

    [
      muxedArray,
      floppedArray,
      passedArray,
      casedArray,
      selectedArray,
      selectedFromArray,
      clonedArray,
      namedArray,
      pipelinedArray,
    ].forEach(_expectLogicArray);
    [
      muxedTypedArray,
      floppedTypedArray,
      passedTypedArray,
      casedTypedArray,
      selectedTypedArray,
      selectedFromTypedArray,
      clonedTypedArray,
      namedTypedArray,
      pipelinedTypedArray,
    ].forEach(_expectTypedLaneArray);
  });

  test('Mux infers nested LogicArrayOf types', () async {
    final control = Logic();
    final d1 = _TypedPacket(name: 'd1');
    final d0 = _TypedPacket(name: 'd0');
    final muxModule = Mux(control, d1, d0);
    await muxModule.build();

    expect(muxModule, isA<TypedOp<_TypedPacket>>());
    expect(muxModule.out, isA<_TypedPacket>());
    expect(muxModule.out.lanes, isA<LogicArrayOf<_TypedLane>>());
    expect(
        muxModule.out.lanes.typedLeafElements, everyElement(isA<_TypedLane>()));

    d0.opcode.put(1);
    d0.lanes.typedLeafElements[0].data.put(0x10);
    d0.lanes.typedLeafElements[1].data.put(0x20);
    d1.opcode.put(6);
    d1.lanes.typedLeafElements[0].data.put(0xa0);
    d1.lanes.typedLeafElements[1].data.put(0xb0);

    control.put(0);
    expect(muxModule.out.opcode.value.toInt(), 1);
    expect(muxModule.out.lanes.typedLeafElements[0].data.value.toInt(), 0x10);
    expect(muxModule.out.lanes.typedLeafElements[1].data.value.toInt(), 0x20);

    control.put(1);
    expect(muxModule.out.opcode.value.toInt(), 6);
    expect(muxModule.out.lanes.typedLeafElements[0].data.value.toInt(), 0xa0);
    expect(muxModule.out.lanes.typedLeafElements[1].data.value.toInt(), 0xb0);
  });

  test('Mux preserves structure type with a constant control', () {
    final d1 = _TypedPacket(name: 'd1');
    final d0 = _TypedPacket(name: 'd0');
    expect(Mux(Const(0), d1, d0).out, isA<_TypedPacket>());
    expect(Mux(Const(1), d1, d0).out, isA<_TypedPacket>());
  });

  test('Mux rejects differently shaped typed arrays', () {
    expect(
        () => Mux(Logic(), _TypedPacket(laneDimensions: const [2, 2]),
            _TypedPacket(laneDimensions: const [4])),
        throwsA(isA<LogicConstructionException>()));
  });

  test('typed operations reject clones, constants, nets, and reset mismatches',
      () {
    expect(() => typedClone(_BadClonePacket()),
        throwsA(isA<LogicConstructionException>()));
    expect(() => Mux<_ConstPacket>(Logic(), _ConstPacket(), _ConstPacket()),
        throwsA(isA<PortTypeException>()));
    expect(() => Passthrough<_NetPacket>(_NetPacket()),
        throwsA(isA<PortTypeException>()));
    expect(
        () => FlipFlop<_TypedPacket>(Logic(), _TypedPacket(),
            reset: Logic(),
            resetValue: _TypedPacket(laneDimensions: const [1, 2])),
        throwsA(isA<LogicConstructionException>()));
    expect(
        () => typedCases(Logic(), {
              0: _TypedPacket(),
              1: _TypedPacket(laneDimensions: const [1, 2])
            }),
        throwsA(isA<LogicConstructionException>()));
    expect(() => <_TypedPacket>[].selectIndexTyped(Logic()),
        throwsA(isA<LogicConstructionException>()));
  });

  test('typed module definitions encode structure and constant reset identity',
      () {
    final sameShapeFirst = Mux<_TypedPacket>(Logic(),
        _TypedPacket(name: 'first_d1'), _TypedPacket(name: 'first_d0'));
    final sameShapeSecond = Mux<_TypedPacket>(Logic(),
        _TypedPacket(name: 'second_d1'), _TypedPacket(name: 'second_d0'));
    final differentShape = Mux<_TypedPacket>(
        Logic(),
        _TypedPacket(laneDimensions: const [1, 2], name: 'different_d1'),
        _TypedPacket(laneDimensions: const [1, 2], name: 'different_d0'));
    final resetZero = FlipFlop<_TypedPacket>(Logic(), _TypedPacket(),
        reset: Logic(), resetValue: 0);
    final resetOne = FlipFlop<_TypedPacket>(Logic(), _TypedPacket(),
        reset: Logic(), resetValue: 1);

    expect(sameShapeFirst.definitionName, sameShapeSecond.definitionName);
    expect(sameShapeFirst.definitionName, isNot(differentShape.definitionName));
    expect(resetZero.definitionName, isNot(resetOne.definitionName));
  });

  test('FlipFlop implements the scalar TypedOp contract', () {
    final flipFlop = FlipFlop(Logic(), Logic(width: 4));
    expect(flipFlop, isA<TypedOp<Logic>>());
    expect(flipFlop.q.runtimeType, Logic);
  });

  test('FlipFlop infers type, reset, and enable behavior', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic();
    final enable = Logic();
    final d = _TypedPacket(name: 'd');
    final flipFlop = FlipFlop(
      clk,
      d,
      en: enable,
      reset: reset,
      resetValue: 0,
    );
    await flipFlop.build();
    unawaited(Simulator.run());

    expect(flipFlop, isA<TypedOp<_TypedPacket>>());
    expect(flipFlop.q, isA<_TypedPacket>());
    expect(flipFlop.q.lanes, isA<LogicArrayOf<_TypedLane>>());

    reset.inject(1);
    enable.inject(0);
    await clk.nextPosedge;
    reset.inject(0);
    expect(flipFlop.q.value, LogicValue.ofInt(0, flipFlop.q.width));

    d.opcode.inject(5);
    d.lanes.typedLeafElements[0].data.inject(0x12);
    d.lanes.typedLeafElements[0].enable.inject(1);
    d.lanes.typedLeafElements[1].data.inject(0x34);
    d.lanes.typedLeafElements[1].enable.inject(0);
    enable.inject(1);
    await clk.nextPosedge;
    expect(flipFlop.q.opcode.value.toInt(), 5);
    expect(flipFlop.q.lanes.typedLeafElements[0].data.value.toInt(), 0x12);
    expect(flipFlop.q.lanes.typedLeafElements[1].data.value.toInt(), 0x34);

    d.opcode.inject(2);
    d.lanes.typedLeafElements[0].data.inject(0xaa);
    enable.inject(0);
    await clk.nextPosedge;
    expect(flipFlop.q.opcode.value.toInt(), 5);
    expect(flipFlop.q.lanes.typedLeafElements[0].data.value.toInt(), 0x12);
    await Simulator.endSimulation();
  });

  test('FlipFlop maps packed reset bits to nested fields', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic();
    final d = _TypedPacket(name: 'reset_order_d');
    final resetValue = LogicValue.ofString('000111100110100101101');
    final flipFlop = FlipFlop(
      clk,
      d,
      reset: reset,
      resetValue: resetValue,
    );
    await flipFlop.build();
    unawaited(Simulator.run());

    reset.inject(1);
    await clk.nextPosedge;
    reset.inject(0);
    expect(flipFlop.q.opcode.value.toInt(), 0x5);
    expect(flipFlop.q.lanes.typedLeafElements[0].data.value.toInt(), 0xa5);
    expect(flipFlop.q.lanes.typedLeafElements[0].enable.value, LogicValue.one);
    expect(flipFlop.q.lanes.typedLeafElements[1].data.value.toInt(), 0x3c);
    expect(flipFlop.q.lanes.typedLeafElements[1].enable.value, LogicValue.zero);
    await Simulator.endSimulation();
  });

  test('typed clone and naming helpers retain concrete field access', () {
    final source = _TypedPacket(name: 'source');
    final clone = source.cloneTyped(name: 'clone');
    final named = source.namedTyped('named');

    expect(clone, isA<_TypedPacket>());
    expect(clone.name, 'clone');
    expect(named, isA<_TypedPacket>());
    expect(named.name, 'named');
    for (var index = 0; index < named.leafElements.length; index++) {
      expect(named.leafElements[index].srcConnections,
          contains(source.leafElements[index]));
    }
  });

  test('Passthrough infers typed contracts', () async {
    final scalar = Passthrough(Logic(width: 4));
    final input = _TypedPacket(name: 'passthrough_input');
    final structured = Passthrough(input);
    await Future.wait([scalar.build(), structured.build()]);

    expect(scalar, isA<TypedOp<Logic>>());
    expect(scalar.out.runtimeType, Logic);
    expect(structured, isA<TypedOp<_TypedPacket>>());
    expect(structured.in_, isA<_TypedPacket>());
    expect(structured.out, isA<_TypedPacket>());
    expect(structured.out.lanes, isA<LogicArrayOf<_TypedLane>>());

    input.opcode.put(5);
    input.lanes.typedLeafElements[0].data.put(0x12);
    input.lanes.typedLeafElements[1].data.put(0x34);
    expect(structured.out.opcode.value.toInt(), 5);
    expect(structured.out.lanes.typedLeafElements[0].data.value.toInt(), 0x12);
    expect(structured.out.lanes.typedLeafElements[1].data.value.toInt(), 0x34);
  });

  test('typedCases preserves structure and selects a default', () {
    final selector = Logic(width: 2);
    final first = _TypedPacket(name: 'first');
    final second = _TypedPacket(name: 'second');
    final fallback = _TypedPacket(name: 'fallback');
    final selected = typedCases(selector, {0: first, 2: second},
        defaultValue: fallback, name: 'selected');

    expect(selected, isA<_TypedPacket>());
    first.opcode.put(1);
    second.opcode.put(2);
    fallback.opcode.put(7);
    selector.put(0);
    expect(selected.opcode.value.toInt(), 1);
    selector.put(2);
    expect(selected.opcode.value.toInt(), 2);
    selector.put(3);
    expect(selected.opcode.value.toInt(), 7);
  });

  test('typed indexed selection works in both invocation directions', () {
    final index = Logic(width: 2);
    final values = [
      _TypedPacket(name: 'value0'),
      _TypedPacket(name: 'value1'),
      _TypedPacket(name: 'value2'),
    ];
    final selectedByList =
        values.selectIndexTyped(index, name: 'selected_by_list');
    final selectedByIndex =
        index.selectFromTyped(values, name: 'selected_by_index');

    for (var valueIndex = 0; valueIndex < values.length; valueIndex++) {
      values[valueIndex].opcode.put(valueIndex + 3);
    }
    index.put(1);
    expect(selectedByList.opcode.value.toInt(), 4);
    expect(selectedByIndex.opcode.value.toInt(), 4);
    index.put(3);
    expect(selectedByList.value, LogicValue.ofInt(0, selectedByList.width));
    expect(selectedByIndex.value, LogicValue.ofInt(0, selectedByIndex.width));
  });

  test('StructurePipeline preserves typed stages and history', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic();
    final stall = Logic();
    final input = _TypedPacket(name: 'pipeline_input');
    final pipeline = StructurePipeline<_TypedPacket>(
      clk,
      input,
      reset: reset,
      resetValue: 0,
      stalls: [null, stall],
      stages: [
        (stage) {
          final next = stage.value.cloneTyped(name: 'stage_0_next');
          next.opcode <= stage.value.opcode + 1;
          for (var lane = 0;
              lane < next.lanes.typedLeafElements.length;
              lane++) {
            next.lanes.typedLeafElements[lane].data <=
                stage.value.lanes.typedLeafElements[lane].data;
            next.lanes.typedLeafElements[lane].enable <=
                stage.value.lanes.typedLeafElements[lane].enable;
          }
          return next;
        },
        (stage) {
          final next = stage.value.cloneTyped(name: 'stage_1_next');
          next.opcode <= stage.value.opcode + stage.get(-1).opcode;
          for (var lane = 0;
              lane < next.lanes.typedLeafElements.length;
              lane++) {
            next.lanes.typedLeafElements[lane].data <=
                stage.value.lanes.typedLeafElements[lane].data;
            next.lanes.typedLeafElements[lane].enable <=
                stage.value.lanes.typedLeafElements[lane].enable;
          }
          return next;
        },
      ],
    );
    unawaited(Simulator.run());

    expect(pipeline.stageCount, 3);
    expect(pipeline.latency, 2);
    expect(pipeline.output, isA<_TypedPacket>());
    expect(pipeline.get(0), same(input));
    expect(pipeline.output.lanes, isA<LogicArrayOf<_TypedLane>>());
    expect(() => pipeline.values.add(input), throwsUnsupportedError);

    reset.inject(1);
    stall.inject(0);
    await clk.nextPosedge;
    reset.inject(0);

    input.opcode.inject(2);
    input.lanes.typedLeafElements[0].data.inject(0x45);
    await clk.nextPosedge;
    input.opcode.inject(4);
    input.lanes.typedLeafElements[0].data.inject(0x67);
    await clk.nextPosedge;
    expect(pipeline.output.opcode.value.toInt(), 7);
    expect(pipeline.output.lanes.typedLeafElements[0].data.value.toInt(), 0x45);

    stall.inject(1);
    input.opcode.inject(1);
    await clk.nextPosedge;
    expect(pipeline.output.opcode.value.toInt(), 7);
    await Simulator.endSimulation();
  });

  test('StructurePipeline treats constant stalls as active-high', () async {
    final clk = SimpleClockGenerator(10).clk;
    final input = _TypedPacket(name: 'constant_stall_input');
    final running = StructurePipeline<_TypedPacket>(
      clk,
      input,
      stalls: [Const(0)],
      stages: [(stage) => stage.value.namedTyped('running_stage')],
    );
    final stalled = StructurePipeline<_TypedPacket>(
      clk,
      input,
      stalls: [Const(1)],
      stages: [(stage) => stage.value.namedTyped('stalled_stage')],
    );
    unawaited(Simulator.run());

    input.opcode.inject(6);
    await clk.nextPosedge;
    expect(running.output.opcode.value.toInt(), 6);
    expect(stalled.output.opcode.value.isValid, isFalse);
    await Simulator.endSimulation();
  });

  test('all structure-preserving operations compile to SystemVerilog',
      () async {
    final harness = _TypedOperationsSynthesisHarness(
      Logic(),
      Logic(),
      Logic(),
      Logic(width: 2),
      _TypedPacket(name: 'first'),
      _TypedPacket(name: 'second'),
    );
    await harness.build();

    SimCompare.checkIverilogVector(harness, const [], buildOnly: true);
  });
}

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

class _ScalarDomainLogic extends Logic {
  final String schema;

  _ScalarDomainLogic({required this.schema, super.name}) : super(width: 4);

  @override
  _ScalarDomainLogic clone({String? name}) =>
      _ScalarDomainLogic(schema: schema, name: name ?? this.name);
}

class _TypedPacket extends LogicStructure {
  Logic get opcode => elements[0];
  TypedLogicArray<_TypedLane, LogicValue> get lanes =>
      elements[1] as TypedLogicArray<_TypedLane, LogicValue>;

  final List<int> laneDimensions;

  _TypedPacket({this.laneDimensions = const [2], String? name})
      : super([
          Logic(name: 'opcode', width: 3),
          TypedLogicArray<_TypedLane, LogicValue>(
              laneDimensions, _TypedLane.new,
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
  Logic get data => elements.single;

  _ConstPacket({int? value = 1, String? name})
      : super([
          if (value == null)
            Logic(name: 'data', width: 4)
          else
            Const(value, width: 4)
        ], name: name ?? 'const_packet');

  @override
  _ConstPacket clone({String? name}) =>
      _ConstPacket(value: null, name: name ?? this.name);
}

class _NetPacket extends LogicStructure {
  _NetPacket({String? name}) : super([LogicNet()], name: name ?? 'net_packet');

  @override
  _NetPacket clone({String? name}) => _NetPacket(name: name ?? this.name);
}

class _ConfiguredPacket extends LogicStructure {
  final String schema;

  _ConfiguredPacket({required this.schema, String? name})
      : super([
          Logic(name: 'data', width: 4),
        ], name: name ?? 'configured_packet');

  Logic get data => elements.single;

  @override
  _ConfiguredPacket clone({String? name}) =>
      _ConfiguredPacket(schema: schema, name: name ?? this.name);
}

class _ConfiguredPacketGenerator {
  final String schema;
  int calls = 0;

  _ConfiguredPacketGenerator(this.schema);

  _ConfiguredPacket call({String? name}) {
    calls++;
    return _ConfiguredPacket(schema: schema, name: name);
  }
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

    final selected = Mux(
      control,
      second,
      first,
      outputGenerator: first.clone,
    ).out;
    final _TypedPacket selectedByCase = cases(
      selector,
      {0: first, 1: second},
      defaultValue: selected,
      outputGenerator: first.clone,
      name: 'selected_by_case',
    );
    final selectedByIndex = [first, second, selectedByCase].selectIndex(
      selector,
      defaultValue: first,
      name: 'selected_by_index',
    );
    final passed = Passthrough.withOutput(
      selectedByIndex,
      outputGenerator: selectedByIndex.clone,
    ).out;
    final registered = FlipFlop(
      clk,
      passed,
      reset: reset,
      resetValue: 0,
      outputGenerator: passed.clone,
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

class _GeneratorVectorHarness extends Module {
  _GeneratorVectorHarness(
    Logic control,
    Logic selector,
    _ConfiguredPacket first,
    _ConfiguredPacket second,
    Logic rawBits,
  ) {
    control = addInput('control', control);
    selector = addInput('selector', selector);
    first = addTypedInput('first', first);
    second = addTypedInput('second', second);
    rawBits = addInput('rawBits', rawBits, width: rawBits.width);

    final muxGenerator = _ConfiguredPacketGenerator('mux');
    final muxed = Mux(
      control,
      second,
      first,
      outputGenerator: muxGenerator.call,
    ).out;
    final caseGenerator = _ConfiguredPacketGenerator('case');
    final selected = cases(
      selector,
      {
        0: muxed,
        1: rawBits,
      },
      outputGenerator: caseGenerator.call,
    );
    final constantGenerator = _ConfiguredPacketGenerator('constant');
    final constantSelected = mux(
      Const(0),
      second,
      first,
      outputGenerator: constantGenerator.call,
    );
    addTypedOutput('out', selected.clone).gets(selected);
    addTypedOutput('constantOut', constantSelected.clone)
        .gets(constantSelected);
  }
}

void _expectLogicArray(LogicArray array) {
  expect(array, isA<LogicArray>());
}

void _expectTypedLaneArray(TypedLogicArray<_TypedLane, LogicValue> array) {
  expect(array, isA<TypedLogicArray<_TypedLane, LogicValue>>());
}

void _expectConst(Const value) {
  expect(value, isA<Const>());
}

void _expectLogic(Logic value) {
  expect(value, isA<Logic>());
}

void main() {
  tearDown(Simulator.reset);

  test('Mux exposes a scalar Logic output', () {
    final muxModule = Mux(Logic(), Logic(width: 4), Logic(width: 4));
    expect(muxModule.out.runtimeType, Logic);
  });

  test('scalar operations explicitly normalize constants and nets', () async {
    final clk = SimpleClockGenerator(10).clk;
    final control = Logic();
    final ordinary = Logic(width: 4);
    final constant = Const(0xa, width: 4);
    final portPrototype = Logic.port('port_data', 4);
    final netDriver = Logic(width: 4);
    final net = LogicNet(width: 4)..gets(netDriver);
    final constantMux = Mux(control, constant, ordinary);
    final constantD0Mux = Mux(control, ordinary, constant);
    final portMux = Mux(control, portPrototype, ordinary);
    final netMux = Mux(control, net, ordinary);
    final netD0Mux = Mux(control, ordinary, net);
    final constantFlop = FlipFlop<Logic>(clk, constant);
    final portFlop = FlipFlop(clk, portPrototype);
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
      constantD0Mux.out,
      portMux.out,
      netMux.out,
      netD0Mux.out,
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
    expect(constantD0Mux.out.value.toInt(), 3);
    expect(portMux.out.value.toInt(), 5);
    expect(netMux.out.value.toInt(), 7);
    expect(netD0Mux.out.value.toInt(), 3);
    control.inject(0);
    await Simulator.tick();
    expect(constantMux.out.value.toInt(), 3);
    expect(constantD0Mux.out.value.toInt(), 0xa);
    expect(netMux.out.value.toInt(), 3);
    expect(netD0Mux.out.value.toInt(), 7);
    await clk.nextPosedge;
    expect(constantFlop.q.value.toInt(), 0xa);
    expect(portFlop.q.value.toInt(), 5);
    expect(netFlop.q.value.toInt(), 7);
    await Simulator.endSimulation();
  });

  test('scalar domain subclasses retain their concrete output type', () async {
    final clk = SimpleClockGenerator(10).clk;
    final control = Logic();
    final d0 = _ScalarDomainLogic(schema: 'd0', name: 'd0');
    final d1 = _ScalarDomainLogic(schema: 'd1', name: 'd1');
    final muxed = Mux(control, d1, d0).out;
    final forwarded = Passthrough(d0).out;
    final registered = FlipFlop(clk, d0).q;

    expect(muxed, isA<_ScalarDomainLogic>());
    expect(muxed.schema, 'd0');
    expect(forwarded, isA<_ScalarDomainLogic>());
    expect(registered, isA<_ScalarDomainLogic>());

    unawaited(Simulator.run());
    d0.inject(0x2);
    d1.inject(0xd);
    control.inject(1);
    await Simulator.tick();
    expect(muxed.value, LogicValue.ofInt(0xd, 4));
    expect(forwarded.value, LogicValue.ofInt(0x2, 4));
    await clk.nextPosedge;
    expect(registered.value, LogicValue.ofInt(0x2, 4));
    await Simulator.endSimulation();
  });

  test('inferred constants and nets reject driveable operation results', () {
    final clk = Logic();
    final control = Logic();
    final constant = Const(3, width: 4);
    final net = LogicNet(width: 4);

    expect(
      () => FlipFlop(clk, constant),
      throwsA(isA<LogicConstructionException>()),
    );
    expect(
      () => FlipFlop(clk, net),
      throwsA(isA<LogicConstructionException>()),
    );
    expect(
      () => Passthrough(constant),
      throwsA(isA<LogicConstructionException>()),
    );
    expect(
      () => Mux(control, Const(1, width: 4), Const(0, width: 4)),
      throwsA(isA<LogicConstructionException>()),
    );
  });

  test('mux constant shortcuts and generators have explicit identities',
      () async {
    final d0 = _ConfiguredPacket(schema: 'd0', name: 'd0');
    final d1 = _ConfiguredPacket(schema: 'd1', name: 'd1');

    expect(mux(Const(0), d1, d0), same(d0));
    expect(mux(Const(1), d1, d0), same(d1));

    final generator = _ConfiguredPacketGenerator('generated');
    final generated = mux(
      Const(0),
      d1,
      d0,
      outputGenerator: generator.call,
    );
    expect(generator.calls, 1);
    expect(generated, isNot(same(d0)));
    expect(generated.schema, 'generated');

    d0.data.put(0x3);
    d1.data.put(0xa);
    await Simulator.tick();
    expect(generated.data.value.toInt(), 0x3);
  });

  test('mux defaults to d0 configuration and generators override it', () async {
    final control = Logic();
    final d0 = _ConfiguredPacket(schema: 'd0', name: 'd0');
    final d1 = _ConfiguredPacket(schema: 'd1', name: 'd1');
    final defaultSchema = Mux(control, d1, d0).out;
    final generator = _ConfiguredPacketGenerator('generated');
    final generatedSchema = Mux(
      control,
      d1,
      d0,
      outputGenerator: generator.call,
    ).out;

    expect(defaultSchema.schema, 'd0');
    expect(generatedSchema.schema, 'generated');
    expect(generator.calls, 1);

    d0.data.put(0x1);
    d1.data.put(0xe);
    control.put(0);
    await Simulator.tick();
    expect(defaultSchema.data.value.toInt(), 0x1);
    expect(generatedSchema.data.value.toInt(), 0x1);
    control.put(1);
    await Simulator.tick();
    expect(defaultSchema.data.value.toInt(), 0xe);
    expect(generatedSchema.data.value.toInt(), 0xe);
  });

  test('flop and passthrough generators override output schemas', () async {
    final clk = SimpleClockGenerator(10).clk;
    final source = _ConfiguredPacket(schema: 'source', name: 'source');
    final passthroughGenerator = _ConfiguredPacketGenerator('passthrough');
    final flopGenerator = _ConfiguredPacketGenerator('flop');
    final forwarded = Passthrough.withOutput(
      source,
      outputGenerator: passthroughGenerator.call,
    ).out;
    final registered = FlipFlop(
      clk,
      source,
      outputGenerator: flopGenerator.call,
    ).q;

    expect(forwarded.schema, 'passthrough');
    expect(registered.schema, 'flop');
    expect(passthroughGenerator.calls, 1);
    expect(flopGenerator.calls, 1);

    unawaited(Simulator.run());
    source.data.inject(0x9);
    await Simulator.tick();
    expect(forwarded.data.value.toInt(), 0x9);
    await clk.nextPosedge;
    expect(registered.data.value.toInt(), 0x9);
    await Simulator.endSimulation();
  });

  test('typed operations infer top-level array types', () {
    final clk = Logic();
    final selector = Logic(width: 2);
    final array0 = LogicArray([2], 4, name: 'array0');
    final array1 = LogicArray([2], 4, name: 'array1');
    final typedArray0 = TypedLogicArray<_TypedLane, LogicValue>(
        [2], _TypedLane.new,
        name: 'typed_array0');
    final typedArray1 = TypedLogicArray<_TypedLane, LogicValue>(
        [2], _TypedLane.new,
        name: 'typed_array1');

    final muxedArray = Mux(selector[0], array1, array0).out;
    final floppedArray = FlipFlop(clk, array0).q;
    final passedArray = Passthrough(array0).out;
    final LogicArray casedArray = cases(selector, {0: array0, 1: array1});
    final selectedArray = [array0, array1].selectIndex(selector);
    final selectedFromArray = selector.selectFrom([array0, array1]);
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
    final TypedLogicArray<_TypedLane, LogicValue> casedTypedArray =
        cases(selector, {0: typedArray0, 1: typedArray1});
    final selectedTypedArray = [typedArray0, typedArray1].selectIndex(selector);
    final selectedFromTypedArray =
        selector.selectFrom([typedArray0, typedArray1]);
    final clonedTypedArray = typedArray0.cloneTyped();
    final namedTypedArray = typedArray0.namedTyped('named_typed_array');
    final pipelinedTypedArray =
        StructurePipeline<TypedLogicArray<_TypedLane, LogicValue>>(
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

  test('Mux infers nested TypedLogicArray types', () async {
    final control = Logic();
    final d1 = _TypedPacket(name: 'd1');
    final d0 = _TypedPacket(name: 'd0');
    final muxModule = Mux(control, d1, d0);
    await muxModule.build();
    expect(muxModule.out, isA<_TypedPacket>());
    expect(muxModule.out.lanes, isA<TypedLogicArray<_TypedLane, LogicValue>>());
    expect(muxModule.out.lanes.arrayElements, everyElement(isA<_TypedLane>()));

    d0.opcode.put(1);
    d0.lanes.arrayElements[0].data.put(0x10);
    d0.lanes.arrayElements[1].data.put(0x20);
    d1.opcode.put(6);
    d1.lanes.arrayElements[0].data.put(0xa0);
    d1.lanes.arrayElements[1].data.put(0xb0);

    control.put(0);
    expect(muxModule.out.opcode.value.toInt(), 1);
    expect(muxModule.out.lanes.arrayElements[0].data.value.toInt(), 0x10);
    expect(muxModule.out.lanes.arrayElements[1].data.value.toInt(), 0x20);

    control.put(1);
    expect(muxModule.out.opcode.value.toInt(), 6);
    expect(muxModule.out.lanes.arrayElements[0].data.value.toInt(), 0xa0);
    expect(muxModule.out.lanes.arrayElements[1].data.value.toInt(), 0xb0);
  });

  test('Mux preserves structure type with a constant control', () {
    final d1 = _TypedPacket(name: 'd1');
    final d0 = _TypedPacket(name: 'd0');
    expect(mux(Const(0), d1, d0), isA<_TypedPacket>());
    expect(mux(Const(1), d1, d0), isA<_TypedPacket>());
  });

  test('Mux rejects differently shaped typed arrays', () {
    expect(
        () => Mux(Logic(), _TypedPacket(laneDimensions: const [2, 2]),
            _TypedPacket(laneDimensions: const [4])),
        throwsA(isA<LogicConstructionException>()));
  });

  test('typed operations consume structures with constant leaves', () async {
    final clk = SimpleClockGenerator(10).clk;
    final control = Logic();
    final constant = _ConstPacket(value: 0xa, name: 'constant');
    final variable = _ConstPacket(value: null, name: 'variable');
    final muxModule = Mux(control, constant, variable);
    final passthrough = Passthrough(constant);
    final flipFlop = FlipFlop(clk, constant);
    await Future.wait([
      muxModule.build(),
      passthrough.build(),
      flipFlop.build(),
    ]);
    for (final module in [muxModule, passthrough, flipFlop]) {
      SimCompare.checkIverilogVector(module, const [], buildOnly: true);
    }

    expect(muxModule.out, isA<_ConstPacket>());
    expect(muxModule.out.hasConsts, isFalse);
    expect(passthrough.out, isA<_ConstPacket>());
    expect(passthrough.out.hasConsts, isFalse);
    expect(flipFlop.q, isA<_ConstPacket>());
    expect(flipFlop.q.hasConsts, isFalse);

    variable.data.inject(3);
    control.inject(0);
    await Simulator.tick();
    expect(muxModule.out.data.value.toInt(), 3);
    expect(passthrough.out.data.value.toInt(), 0xa);

    control.inject(1);
    await Simulator.tick();
    expect(muxModule.out.data.value.toInt(), 0xa);

    unawaited(Simulator.run());
    await clk.nextPosedge;
    expect(flipFlop.q.data.value.toInt(), 0xa);
    await Simulator.endSimulation();
  });

  test('explicit Logic flops constants through reset without mutating source',
      () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic();
    final constant = Const(0xa, width: 4);
    final q = flop<Logic>(
      clk,
      constant,
      reset: reset,
      resetValue: 0,
    );

    expect(q, isA<Logic>());
    expect(q, isNot(isA<Const>()));
    expect(constant.value, LogicValue.ofInt(0xa, 4));

    unawaited(Simulator.run());
    reset.inject(1);
    await clk.nextPosedge;
    expect(q.value, LogicValue.ofInt(0, 4));
    reset.inject(0);
    await clk.nextPosedge;
    expect(q.value, LogicValue.ofInt(0xa, 4));
    expect(constant.value, LogicValue.ofInt(0xa, 4));
    await Simulator.endSimulation();
  });

  test('typed operations reject clones, nets, and reset mismatches', () {
    expect(() => _BadClonePacket().cloneTyped(),
        throwsA(isA<LogicConstructionException>()));
    expect(() => Passthrough<_NetPacket>(_NetPacket()),
        throwsA(isA<LogicConstructionException>()));
    expect(
        () => FlipFlop<_TypedPacket>(Logic(), _TypedPacket(),
            reset: Logic(),
            resetValue: _TypedPacket(laneDimensions: const [1, 2])),
        throwsA(isA<LogicConstructionException>()));
    expect(
        () => cases<_TypedPacket>(Logic(), {
              0: _TypedPacket(),
              1: _TypedPacket(laneDimensions: const [1, 2])
            }),
        throwsA(isA<LogicConstructionException>()));
    expect(() => <_TypedPacket>[].selectIndex(Logic()),
        throwsA(isA<LogicConstructionException>()));
  });

  test('cases rejects mismatched LogicValue widths', () {
    final selector = Logic(width: 2);
    final first = _TypedPacket(name: 'first');
    final second = _TypedPacket(name: 'second');

    expect(
      () => cases(selector, {
        LogicValue.ofInt(4, 3): first,
        1: second,
      }),
      throwsA(isA<SignalWidthMismatchException>()),
    );
    expect(
      () => cases(
        selector,
        {0: first, 1: second},
        defaultValue: LogicValue.ofInt(0, first.width + 1),
      ),
      throwsA(isA<SignalWidthMismatchException>()),
    );
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

  test('FlipFlop exposes a scalar Logic output', () {
    final flipFlop = FlipFlop(Logic(), Logic(width: 4));
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
    expect(flipFlop.q, isA<_TypedPacket>());
    expect(flipFlop.q.lanes, isA<TypedLogicArray<_TypedLane, LogicValue>>());

    reset.inject(1);
    enable.inject(0);
    await clk.nextPosedge;
    reset.inject(0);
    expect(flipFlop.q.value, LogicValue.ofInt(0, flipFlop.q.width));

    d.opcode.inject(5);
    d.lanes.arrayElements[0].data.inject(0x12);
    d.lanes.arrayElements[0].enable.inject(1);
    d.lanes.arrayElements[1].data.inject(0x34);
    d.lanes.arrayElements[1].enable.inject(0);
    enable.inject(1);
    await clk.nextPosedge;
    expect(flipFlop.q.opcode.value.toInt(), 5);
    expect(flipFlop.q.lanes.arrayElements[0].data.value.toInt(), 0x12);
    expect(flipFlop.q.lanes.arrayElements[1].data.value.toInt(), 0x34);

    d.opcode.inject(2);
    d.lanes.arrayElements[0].data.inject(0xaa);
    enable.inject(0);
    await clk.nextPosedge;
    expect(flipFlop.q.opcode.value.toInt(), 5);
    expect(flipFlop.q.lanes.arrayElements[0].data.value.toInt(), 0x12);
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
    expect(flipFlop.q.lanes.arrayElements[0].data.value.toInt(), 0xa5);
    expect(flipFlop.q.lanes.arrayElements[0].enable.value, LogicValue.one);
    expect(flipFlop.q.lanes.arrayElements[1].data.value.toInt(), 0x3c);
    expect(flipFlop.q.lanes.arrayElements[1].enable.value, LogicValue.zero);
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

  test('typed clone and naming distinguish constants from aliases', () {
    final constant = Const(0x5, width: 4);
    final constantClone = constant.cloneTyped();
    _expectConst(constantClone);
    expect(constantClone, isA<Const>());
    expect(constantClone.value, constant.value);
    expect(
      () => constant.namedTyped('constant_alias'),
      throwsA(isA<LogicConstructionException>()),
    );

    final widenedConstant = constant as Logic;
    final alias = widenedConstant.namedTyped('constant_alias');
    _expectLogic(alias);
    expect(alias, isNot(isA<Const>()));
    expect(alias.value, constant.value);

    final net = LogicNet(width: 4);
    final netClone = net.cloneTyped();
    final netAlias = net.namedTyped('net_alias');
    expect(netClone, isA<LogicNet>());
    expect(netAlias, isA<LogicNet>());

    final packet = _TypedPacket(name: 'packet');
    final widenedPacket = packet as Logic;
    final widenedClone = widenedPacket.cloneTyped(name: 'packet_clone');
    _expectLogic(widenedClone);
    expect(widenedClone, isA<_TypedPacket>());

    final constantPacket = _ConstPacket(name: 'constant_packet');
    final namedPacket = constantPacket.namedTyped('named_packet');
    expect(namedPacket, isA<_ConstPacket>());
    expect(namedPacket.hasConsts, isFalse);
  });

  test('Passthrough infers typed contracts', () async {
    final scalar = Passthrough(Logic(width: 4));
    final input = _TypedPacket(name: 'passthrough_input');
    final structured = Passthrough(input);
    await Future.wait([scalar.build(), structured.build()]);
    expect(scalar.out.runtimeType, Logic);
    expect(structured.in_, isA<_TypedPacket>());
    expect(structured.out, isA<_TypedPacket>());
    expect(
        structured.out.lanes, isA<TypedLogicArray<_TypedLane, LogicValue>>());

    input.opcode.put(5);
    input.lanes.arrayElements[0].data.put(0x12);
    input.lanes.arrayElements[1].data.put(0x34);
    expect(structured.out.opcode.value.toInt(), 5);
    expect(structured.out.lanes.arrayElements[0].data.value.toInt(), 0x12);
    expect(structured.out.lanes.arrayElements[1].data.value.toInt(), 0x34);
  });

  test('cases preserves structure and selects a default', () {
    final selector = Logic(width: 2);
    final first = _TypedPacket(name: 'first');
    final second = _TypedPacket(name: 'second');
    final fallback = _TypedPacket(name: 'fallback');
    final _TypedPacket selected = cases(selector, {0: first, 2: second},
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

  test('cases uses an explicit generator for mixed packed sources', () {
    final selector = Logic();
    final packet = _ConfiguredPacket(schema: 'packet', name: 'packet');
    final packed = Logic(width: packet.width);
    final generator = _ConfiguredPacketGenerator('generated');
    final selected = cases(
      selector,
      {
        0: packet,
        1: packed,
      },
      outputGenerator: generator.call,
    );

    expect(selected, isA<_ConfiguredPacket>());
    expect(selected.schema, 'generated');
    expect(generator.calls, 1);
    packet.data.put(0x4);
    packed.put(0xb);
    selector.put(0);
    expect(selected.data.value.toInt(), 0x4);
    selector.put(1);
    expect(selected.data.value.toInt(), 0xb);
  });

  test('generator-backed mux and cases match functional and SV vectors',
      () async {
    final harness = _GeneratorVectorHarness(
      Logic(),
      Logic(),
      _ConfiguredPacket(schema: 'first', name: 'first'),
      _ConfiguredPacket(schema: 'second', name: 'second'),
      Logic(width: 4),
    );
    await harness.build();

    final vectors = [
      Vector(
        {
          'control': 0,
          'selector': 0,
          'first': 0x3,
          'second': 0xc,
          'rawBits': 0xe,
        },
        {'out': 0x3, 'constantOut': 0x3},
      ),
      Vector(
        {
          'control': 1,
          'selector': 0,
          'first': 0x3,
          'second': 0xc,
          'rawBits': 0xe,
        },
        {'out': 0xc, 'constantOut': 0x3},
      ),
      Vector(
        {
          'control': 1,
          'selector': 1,
          'first': 0x3,
          'second': 0xc,
          'rawBits': 0xe,
        },
        {'out': 0xe, 'constantOut': 0x3},
      ),
    ];
    await SimCompare.checkFunctionalVector(harness, vectors);
    SimCompare.checkIverilogVector(harness, vectors);
  });

  test('typed indexed selection works in both invocation directions', () {
    final index = Logic(width: 2);
    final values = [
      _TypedPacket(name: 'value0'),
      _TypedPacket(name: 'value1'),
      _TypedPacket(name: 'value2'),
    ];
    final selectedByList = values.selectIndex(index, name: 'selected_by_list');
    final selectedByIndex = index.selectFrom(values, name: 'selected_by_index');

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
          for (var lane = 0; lane < next.lanes.arrayElements.length; lane++) {
            next.lanes.arrayElements[lane].data <=
                stage.value.lanes.arrayElements[lane].data;
            next.lanes.arrayElements[lane].enable <=
                stage.value.lanes.arrayElements[lane].enable;
          }
          return next;
        },
        (stage) {
          final next = stage.value.cloneTyped(name: 'stage_1_next');
          next.opcode <= stage.value.opcode + stage.get(-1).opcode;
          for (var lane = 0; lane < next.lanes.arrayElements.length; lane++) {
            next.lanes.arrayElements[lane].data <=
                stage.value.lanes.arrayElements[lane].data;
            next.lanes.arrayElements[lane].enable <=
                stage.value.lanes.arrayElements[lane].enable;
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
    expect(
        pipeline.output.lanes, isA<TypedLogicArray<_TypedLane, LogicValue>>());
    expect(() => pipeline.values.add(input), throwsUnsupportedError);

    reset.inject(1);
    stall.inject(0);
    await clk.nextPosedge;
    reset.inject(0);

    input.opcode.inject(2);
    input.lanes.arrayElements[0].data.inject(0x45);
    await clk.nextPosedge;
    input.opcode.inject(4);
    input.lanes.arrayElements[0].data.inject(0x67);
    await clk.nextPosedge;
    expect(pipeline.output.opcode.value.toInt(), 7);
    expect(pipeline.output.lanes.arrayElements[0].data.value.toInt(), 0x45);

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

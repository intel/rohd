// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_test.dart
// Tests for Interface
//
// 2021 November 30
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum MyDirection { dir1, dir2 }

enum _CaptureDirection { input, output }

class _EmptyModule extends Module {}

class _Payload extends LogicStructure implements PayloadShapeMetadata {
  @override
  final String payloadShapeMetadata;

  _Payload(this.payloadShapeMetadata, {super.name})
      : super([Logic(name: 'bits', width: 8)]);

  @override
  _Payload clone({String? name}) =>
      _Payload(payloadShapeMetadata, name: name ?? this.name);
}

class _PayloadInterface extends Interface<MyDirection> {
  final TypedInterfacePortPolicy policy;
  final Logic schema;

  _PayloadInterface(this.schema, this.policy) {
    setPorts([schema], [MyDirection.dir1]);
  }

  @override
  Map<String, TypedInterfacePortPolicy> get typedPayloadPorts =>
      {schema.name: policy};

  @override
  _PayloadInterface clone() => _PayloadInterface(schema.cloneTyped(), policy);
}

class _NetPayload extends LogicNet implements PayloadShapeMetadata {
  @override
  final String payloadShapeMetadata;

  _NetPayload(this.payloadShapeMetadata, {super.name}) : super(width: 8);

  @override
  _NetPayload clone({String? name}) =>
      _NetPayload(payloadShapeMetadata, name: name ?? this.name);
}

class _TypedPair extends PairInterface {
  final Logic data;

  _TypedPair(this.data) : super(portsFromProvider: [data]);

  @override
  Map<String, TypedInterfacePortPolicy> get typedPayloadPorts =>
      {data.name: TypedInterfacePortPolicy.packedBridge};

  @override
  _TypedPair clone() => _TypedPair(data.cloneTyped());
}

class _NestedPair extends PairInterface {
  late final _TypedPair child;

  _NestedPair() {
    child = addSubInterface('child', _TypedPair(_Payload('a', name: 'data')),
        uniquify: (name) => 'child_$name');
  }

  @override
  _NestedPair clone() => _NestedPair();
}

class _BadPayload extends Logic implements PayloadShapeMetadata {
  @override
  final String payloadShapeMetadata;

  _BadPayload({this.payloadShapeMetadata = 'original', super.name})
      : super(width: 8);

  @override
  _BadPayload clone({String? name}) =>
      _BadPayload(payloadShapeMetadata: 'changed', name: name ?? this.name);
}

class _BadNestedPayload extends LogicStructure {
  _BadNestedPayload({bool changed = false, super.name})
      : super([
          _BadPayload(
              payloadShapeMetadata: changed ? 'changed' : 'original',
              name: 'bits')
        ]);

  @override
  _BadNestedPayload clone({String? name}) =>
      _BadNestedPayload(changed: true, name: name ?? this.name);
}

class _TypedPayloadHarness extends Module {
  _TypedPayloadHarness(_PayloadInterface incoming, _PayloadInterface outgoing,
      {bool manual = false}) {
    final localInput = _PayloadInterface(
        _Payload('word', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    final localOutput = _PayloadInterface(
        _Payload('word', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    if (manual) {
      final bridge = localInput.schema.cloneTyped(name: 'data_input_bridge')
        ..gets(incoming.schema);
      localInput.schema <= addTypedInput<Logic>('in_data', bridge);
      final output =
          addTypedOutput<Logic>('out_data', localOutput.schema.cloneTyped);
      output <= localOutput.schema;
      outgoing.schema <= output;
    } else {
      localInput.connectIO(this, incoming,
          inputTags: [MyDirection.dir1], uniquify: (name) => 'in_$name');
      localOutput.connectIO(this, outgoing,
          outputTags: [MyDirection.dir1], uniquify: (name) => 'out_$name');
    }
    localOutput.schema <= localInput.schema;
  }
}

class _TypedPayloadTop extends Module {
  late final _TypedPayloadHarness child;

  _TypedPayloadTop({bool manual = false}) {
    final incoming = _PayloadInterface(
        _Payload('word', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    final outgoing = _PayloadInterface(
        Logic(name: 'data', width: 8), TypedInterfacePortPolicy.packedBridge);
    incoming.schema <= addInput('source', Logic(width: 8), width: 8);
    child = _TypedPayloadHarness(incoming, outgoing, manual: manual);
    addOutput('result', width: 8) <= outgoing.schema;
  }
}

class _TypedInOutChild extends Module {
  _TypedInOutChild(_PayloadInterface external, Logic enable, Logic value) {
    final local = _PayloadInterface(_NetPayload('word', name: 'data'),
        TypedInterfacePortPolicy.packedBridge)
      ..connectIO(this, external, inOutTags: [MyDirection.dir1]);
    enable = addInput('enable', enable);
    value = addInput('value', value, width: 8);
    local.schema <= TriStateBuffer(value, enable: enable).out;
    addOutput('observed', width: 8) <= local.schema;
  }
}

class _TypedInOutTop extends Module {
  _TypedInOutTop() {
    final bus = LogicNet(name: 'data', width: 8);
    final external =
        _PayloadInterface(bus, TypedInterfacePortPolicy.packedBridge);
    final externalEnable = addInput('external_enable', Logic());
    final externalValue = addInput('external_value', Logic(width: 8), width: 8);
    final internalEnable = addInput('internal_enable', Logic());
    final internalValue = addInput('internal_value', Logic(width: 8), width: 8);
    bus <= TriStateBuffer(externalValue, enable: externalEnable).out;
    final child = _TypedInOutChild(external, internalEnable, internalValue);
    addOutput('external_observed', width: 8) <= bus;
    addOutput('internal_observed', width: 8) <= child.output('observed');
  }
}

class _ClockDataInterface extends Interface<_CaptureDirection> {
  final bool clockFirst;

  Logic get clock => port('clock');
  Logic get data => port('data');
  Logic get result => port('result');

  _ClockDataInterface({required this.clockFirst}) {
    final inputs = [
      Logic.port('clock'),
      Logic.port('data'),
    ];
    setPorts(
      clockFirst ? inputs : inputs.reversed.toList(),
      [_CaptureDirection.input],
    );
    setPorts([Logic.port('result')], [_CaptureDirection.output]);
  }

  @override
  _ClockDataInterface clone() => _ClockDataInterface(clockFirst: clockFirst);
}

class _ClockDataCapture extends Module {
  _ClockDataCapture(_ClockDataInterface interface) {
    final local = _ClockDataInterface(clockFirst: interface.clockFirst)
      ..connectIO(
        this,
        interface,
        inputTags: {_CaptureDirection.input},
        outputTags: {_CaptureDirection.output},
      );

    Sequential(local.clock, [local.result < local.data]);
  }
}

class MyModuleInterface extends Interface<MyDirection> {
  MyModuleInterface() {
    setPorts([Logic.port('p1'), LogicArray.port('p1arr')], [MyDirection.dir1]);
    setPorts(
        [LogicNet.port('p2'), LogicArray.netPort('p2arr')], [MyDirection.dir2]);
  }

  @override
  MyModuleInterface clone() => MyModuleInterface();
}

class MyModule extends Module {
  MyModule(MyModuleInterface i1, MyModuleInterface i2) {
    MyModuleInterface().connectIO(this, i1,
        uniquify: (oldName) => 'i1$oldName',
        inOutTags: {MyDirection.dir2},
        inputTags: {MyDirection.dir1});
    MyModuleInterface().connectIO(this, i2,
        uniquify: (oldName) => 'i2$oldName',
        inOutTags: {MyDirection.dir2},
        outputTags: {MyDirection.dir1});
  }
}

class ModuleWithaddInterfacePortss extends Module {
  ModuleWithaddInterfacePortss(
      Interface<MyDirection> intf1, Interface<MyDirection> intf2) {
    intf1 = addInterfacePorts(
      intf1,
      inputTags: {MyDirection.dir1},
      outputTags: {MyDirection.dir2},
      uniquify: (oldName) => 'i1$oldName',
    );
    intf2 = addInterfacePorts(
      intf2,
      inputTags: {MyDirection.dir2},
      outputTags: {MyDirection.dir1},
      uniquify: (oldName) => 'i2$oldName',
    );

    intf1.driveOther(intf2, [MyDirection.dir1]);
    intf2.driveOther(intf1, [MyDirection.dir2]);
  }
}

class UncleanPortInterface extends Interface<MyDirection> {
  UncleanPortInterface() {
    setPorts([Logic.port('end')], [MyDirection.dir1]);
  }

  @override
  UncleanPortInterface clone() => UncleanPortInterface();
}

class DuplicatePortInterface extends Interface<MyDirection> {
  DuplicatePortInterface() {
    setPorts([Logic.port('dup')], [MyDirection.dir1]);
    setPorts([Logic.port('dup')], [MyDirection.dir2]);
  }

  @override
  DuplicatePortInterface clone() => DuplicatePortInterface();
}

class MaybePortInterface extends Interface<MyDirection> {
  Logic? get p => tryPort('p');

  final bool includePort;
  MaybePortInterface({required this.includePort}) {
    if (includePort) {
      setPorts([Logic.port('p')], {MyDirection.dir1});
    }
  }

  @override
  MaybePortInterface clone() => MaybePortInterface(includePort: includePort);
}

class BadNetInterface extends Interface<MyDirection> {
  BadNetInterface() {
    setPorts([Logic.port('p')], [MyDirection.dir1]);
    setPorts([LogicArray.port('a')], [MyDirection.dir2]);
  }

  @override
  BadNetInterface clone() => BadNetInterface();
}

class BadNetModule extends Module {
  BadNetModule({bool badPort = false, bool badArr = false}) {
    BadNetInterface().connectIO(this, BadNetInterface(), inOutTags: {
      if (badPort) MyDirection.dir1,
      if (badArr) MyDirection.dir2,
    });
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('schema-aware interface input and output preserve bridges', () async {
    final dut = _TypedPayloadTop();
    expect(dut.child.input('in_data'), isA<_Payload>());
    expect(dut.child.output('out_data'), isA<_Payload>());
    await dut.build();
    final vectors = [
      Vector({'source': LogicValue.ofString('10xz0101')},
          {'result': LogicValue.ofString('10xz0101')}),
      Vector({'source': 0x5a}, {'result': 0x5a}),
    ];
    await SimCompare.checkFunctionalVector(dut, vectors);
    SimCompare.checkIverilogVector(dut, vectors);
  });

  test('schema-aware ports reject mismatches only when selected', () {
    _PayloadInterface interface(
            Logic payload, TypedInterfacePortPolicy policy) =>
        _PayloadInterface(payload, policy);
    final first = interface(
        _Payload('a', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    final second = interface(
        _Payload('b', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    expect(
        () => first
            .connectIO(_EmptyModule(), second, inputTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
    expect(
        () => first
            .connectIO(_EmptyModule(), second, outputTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
    first.connectIO(_EmptyModule(), second, inputTags: [MyDirection.dir2]);
    final strict = interface(
        _Payload('a', name: 'data'), TypedInterfacePortPolicy.matching);
    final packed = interface(
        Logic(name: 'data', width: 8), TypedInterfacePortPolicy.matching);
    expect(
        () => strict
            .connectIO(_EmptyModule(), packed, inputTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
    final wrongWidth = interface(
        Logic(name: 'data', width: 7), TypedInterfacePortPolicy.packedBridge);
    expect(
        () => first.connectIO(_EmptyModule(), wrongWidth,
            inputTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
  });

  test('schema-aware inout ports retain net domains and reject mixed roles',
      () {
    final local = _PayloadInterface(
        _NetPayload('a', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    final source = _PayloadInterface(LogicNet(name: 'data', width: 8),
        TypedInterfacePortPolicy.packedBridge);
    final module = _EmptyModule();
    local.connectIO(module, source, inOutTags: [MyDirection.dir1]);
    expect(module.inOut('data'), isA<_NetPayload>());

    final conflict = _PayloadInterface(
        _NetPayload('a', name: 'data'), TypedInterfacePortPolicy.packedBridge);
    expect(
        () => conflict.connectIO(_EmptyModule(), source,
            inputTags: [MyDirection.dir1], inOutTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
    final nonNet = _PayloadInterface(
        Logic(name: 'data', width: 8), TypedInterfacePortPolicy.packedBridge);
    expect(
        () => conflict
            .connectIO(_EmptyModule(), nonNet, inOutTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
  });

  test('schema-aware inout bridges resolve drives in both directions',
      () async {
    final dut = _TypedInOutTop();
    await dut.build();
    final vectors = [
      Vector({
        'external_enable': 1,
        'external_value': 0x5a,
        'internal_enable': 0,
        'internal_value': 0xa5,
      }, {
        'external_observed': 0x5a,
        'internal_observed': 0x5a,
      }),
      Vector({
        'external_enable': 0,
        'external_value': 0x5a,
        'internal_enable': 1,
        'internal_value': 0xa5,
      }, {
        'external_observed': 0xa5,
        'internal_observed': 0xa5,
      }),
      Vector({
        'external_enable': 1,
        'external_value': 0x5a,
        'internal_enable': 1,
        'internal_value': 0xa5,
      }, {
        'external_observed': LogicValue.ofString('xxxxxxxx'),
        'internal_observed': LogicValue.ofString('xxxxxxxx'),
      }),
      Vector({
        'external_enable': 0,
        'external_value': 0,
        'internal_enable': 0,
        'internal_value': 0,
      }, {
        'external_observed': LogicValue.ofString('zzzzzzzz'),
        'internal_observed': LogicValue.ofString('zzzzzzzz'),
      }),
    ];
    await SimCompare.checkFunctionalVector(dut, vectors);
    SimCompare.checkIverilogVector(dut, vectors);
  });

  test('schema-aware nested pair ports retain names and types', () {
    final source = _NestedPair();
    final module = _EmptyModule();
    source.clone().pairConnectIO(module, source, PairRole.consumer,
        uniquify: (name) => 'outer_$name');
    expect(module.input('outer_child_data'), isA<_Payload>());
  });

  test('schema-aware ports reject different array codecs', () {
    LogicValue encode(LogicValue value) => value;
    final alternate =
        LogicValueCodec<LogicValue>(decode: encode, encode: encode);
    Logic array(LogicValueCodec<LogicValue> codec) =>
        TypedLogicArray<Logic, LogicValue>(
            [2], ({name}) => Logic(width: 4, name: name),
            name: 'data', valueCodec: codec);
    final local = _PayloadInterface(array(LogicValueCodec.logicValue),
        TypedInterfacePortPolicy.packedBridge);
    final source = _PayloadInterface(
        array(alternate), TypedInterfacePortPolicy.packedBridge);
    expect(
        () => local
            .connectIO(_EmptyModule(), source, inputTags: [MyDirection.dir1]),
        throwsA(isA<PortTypeException>()));
  });

  test('schema-aware ports reject nested schema-changing clones', () {
    final local = _PayloadInterface(
        _BadNestedPayload(name: 'data'), TypedInterfacePortPolicy.packedBridge);
    final source = _PayloadInterface(
        Logic(name: 'data', width: 8), TypedInterfacePortPolicy.packedBridge);
    expect(
        () => local
            .connectIO(_EmptyModule(), source, inputTags: [MyDirection.dir1]),
        throwsA(isA<LogicConstructionException>()));
    expect(
        () => local
            .connectIO(_EmptyModule(), source, outputTags: [MyDirection.dir1]),
        throwsA(isA<LogicConstructionException>()));
  });

  test('schema-aware checks add no RTL compared with manual registration',
      () async {
    final automatic = _TypedPayloadTop();
    final manual = _TypedPayloadTop(manual: true);
    await automatic.build();
    await manual.build();
    String withoutTimestamp(Module module) => module
        .dumpSystemVerilog()
        .replaceFirst(RegExp(r' \* Generation time:.*\n'), '');
    expect(withoutTimestamp(automatic), withoutTimestamp(manual));
  });

  group('uniquified interfaces', () {
    test('get uniquified ports', () async {
      final m = MyModule(MyModuleInterface(), MyModuleInterface());
      await m.build();

      expect(m.tryOutput('i2p1'), isNotNull);
      expect(m.tryOutput('i2p1arr'), isNotNull);

      expect(m.tryInput('i1p1'), isNotNull);
      expect(m.tryInput('i1p1arr'), isNotNull);

      expect(m.tryInOut('i1p2'), isNotNull);
      expect(m.tryInOut('i1p2arr'), isNotNull);
      expect(m.tryInOut('i2p2'), isNotNull);
      expect(m.tryInOut('i2p2arr'), isNotNull);
    });
  });

  test('connect interfaces module api', () async {
    final intf1 = MyModuleInterface();
    final intf2 = MyModuleInterface();

    final mod = ModuleWithaddInterfacePortss(intf1, intf2);
    await mod.build();

    expect(mod.tryInput('i1p1'), isNotNull);
    expect(mod.tryOutput('i1p2'), isNotNull);
    expect(mod.tryInput('i2p2'), isNotNull);
    expect(mod.tryOutput('i2p1'), isNotNull);

    final vectors = [
      Vector({'i1p1': 1, 'i2p2': 0}, {'i1p2': 0, 'i2p1': 1}),
      Vector({'i1p1': 0, 'i2p2': 1}, {'i1p2': 1, 'i2p1': 0}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('clock and data connection order preserves sequential capture',
      () async {
    final vectors = [
      Vector({'clock': 0, 'data': 0}, {}),
      Vector({'clock': 1}, {'result': 0}),
      Vector({'clock': 0, 'data': 1}, {'result': 0}),
      Vector({'clock': 1}, {'result': 1}),
    ];

    for (final clockFirst in [true, false]) {
      await Simulator.reset();
      final mod = _ClockDataCapture(
        _ClockDataInterface(clockFirst: clockFirst),
      );
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    }
  });

  test('should return exception when port name is not sanitary.', () {
    expect(() {
      UncleanPortInterface();
    }, throwsException);
  });

  test('adding a port with a name already on the interface throws', () {
    expect(
        DuplicatePortInterface.new, throwsA(isA<DuplicatePortNameException>()));
  });

  group('bad net args intf', () {
    test('port', () {
      expect(
          () => BadNetModule(badPort: true), throwsA(isA<PortTypeException>()));
    });

    test('array', () {
      expect(
          () => BadNetModule(badArr: true), throwsA(isA<PortTypeException>()));
    });
  });

  group('maybe port', () {
    test('tryPort, exists', () {
      final intf = MaybePortInterface(includePort: true);
      expect(intf.p, isNotNull);
    });

    test('tryPort, doesnt exist', () {
      final intf = MaybePortInterface(includePort: false);
      expect(intf.p, null);
    });
  });
}

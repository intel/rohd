// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_port_test.dart
// Tests for matching ports on modules
//
// 2025 July
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import 'payload_shape_test_utils.dart';

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  final bool asNet;

  factory MyStruct({String? name, bool asNet = false}) => MyStruct._(
        (asNet ? LogicNet.new : Logic.new)(
            name: 'ready', naming: Naming.mergeable),
        (asNet ? LogicNet.new : Logic.new)(
            name: 'valid', naming: Naming.mergeable),
        name: name,
        asNet: asNet,
      );

  MyStruct._(this.ready, this.valid,
      {required String? name, required this.asNet})
      : super([ready, valid], name: name ?? 'myStruct');

  @override
  MyStruct clone({String? name}) =>
      MyStruct(name: name ?? this.name, asNet: asNet);
}

class SimpleStructModule extends Module {
  late final MyStruct myOut;

  SimpleStructModule(MyStruct myIn, {super.name = 'simple_struct_mod'}) {
    myIn = (myIn.isNet ? addTypedInOut : addTypedInput)('myIn', myIn);

    final internal = myIn.clone(name: 'internal_struct');
    internal.ready <= myIn.valid;
    internal.valid <= myIn.ready;

    if (myIn.isNet) {
      myOut = myIn.clone(name: 'myOutExt');
      addTypedInOut('myOut', myOut) <= internal;
    } else {
      myOut = addTypedOutput('myOut', internal.clone)..gets(internal);
    }
  }
}

class OneBitStruct extends LogicStructure {
  OneBitStruct({super.name = 'obs'}) : super([Logic(name: 'oneBit')]);

  @override
  OneBitStruct clone({String? name}) => OneBitStruct(name: name ?? this.name);
}

class ModuleWithOneBitStructPort extends Module {
  ModuleWithOneBitStructPort(OneBitStruct inStruct) {
    inStruct = addTypedInput('inStruct', inStruct);
    final outStruct = addTypedOutput('outStruct', inStruct.clone);

    outStruct.elements.first.gets(inStruct.elements.first);
  }
}

class SimpleStructModuleContainer extends Module {
  SimpleStructModuleContainer(Logic a1, Logic a2,
      {super.name = 'simple_struct_mod_container', bool asNet = false}) {
    final Logic Function(String, Logic) inMaker = asNet ? addInOut : addInput;
    Logic makeOutput(String name) =>
        asNet ? addInOut(name, LogicNet(name: 'ext$name')) : addOutput(name);

    a1 = inMaker('a1', a1);
    a2 = inMaker('a2', a2);
    final upperStruct = MyStruct(name: 'upper_struct', asNet: asNet);
    upperStruct.ready <= a1;
    upperStruct.valid <= a2;
    final sub = SimpleStructModule(upperStruct);

    makeOutput('b1') <= sub.myOut.ready;
    makeOutput('b2') <= sub.myOut.valid;
  }
}

class DummyModule extends Module {}

class CloneNoNameStruct extends LogicStructure {
  CloneNoNameStruct({bool asNet = false})
      : super([if (asNet) LogicNet() else Logic()], name: 'abc');

  @override
  CloneNoNameStruct clone({String? name}) => CloneNoNameStruct();
}

class MatcherModule extends Module {
  final bool isNet;

  Logic get anyOut => isNet ? inOutSource('anyOut') : output('anyOut');

  @protected
  late final Logic _innerOut;

  @protected
  late final Logic _anyIn;

  MatcherModule(Logic anyIn) : isNet = anyIn.isNet {
    if (isNet) {
      _anyIn = addTypedInOut('anyIn', anyIn);
      _innerOut = addTypedInOut('anyOut', anyIn.clone());
    } else {
      _anyIn = addTypedInput('anyIn', anyIn);
      _innerOut = addTypedOutput('anyOut', _anyIn.clone);
    }

    _makeLogic();
  }

  void _makeLogic() {
    _innerOut <= ~_anyIn;
  }
}

class MatcherModuleWrapper extends MatcherModule {
  MatcherModuleWrapper(super.anyIn);
  @override
  void _makeLogic() {
    _innerOut <= MatcherModule(_anyIn).anyOut;
  }
}

class MatcherPassThrough extends MatcherModule {
  MatcherPassThrough(super.anyIn);

  @override
  void _makeLogic() {
    _innerOut <= _anyIn;
  }
}

class PartialLogicNetStructAssignment extends Module {
  PartialLogicNetStructAssignment(MyStruct a) {
    a = addTypedInOut('a', a);

    final b = addTypedInOut('b', a.clone());

    b.valid <= a.valid;
  }
}

class StructWithConst extends LogicStructure {
  StructWithConst({super.name}) : super([Logic(), Const(1)]);

  @override
  StructWithConst clone({String? name}) => StructWithConst(name: name);
}

class StructWithConstAndDriveableClone extends LogicStructure {
  Logic get data => elements.single;

  StructWithConstAndDriveableClone.constant({String? name})
      : this._(Const(1), name: name);

  StructWithConstAndDriveableClone._(Logic data, {super.name}) : super([data]);

  @override
  StructWithConstAndDriveableClone clone({String? name}) =>
      StructWithConstAndDriveableClone._(Logic(), name: name);
}

class _ConstWithNetClone extends LogicStructure {
  _ConstWithNetClone(Logic element, {super.name}) : super([element]);

  @override
  _ConstWithNetClone clone({String? name}) =>
      _ConstWithNetClone(LogicNet(), name: name);
}

class _MixedConstantStructure extends LogicStructure {
  Logic get data => elements[0];
  Logic get fixedBits => elements[1];

  _MixedConstantStructure(Logic data, Logic fixedBits, {super.name})
      : super([data, fixedBits]);

  @override
  _MixedConstantStructure clone({String? name}) => _MixedConstantStructure(
        Logic(name: 'data', width: 2),
        Logic(name: 'fixedBits', width: 2),
        name: name ?? this.name,
      );
}

class _FormatSignal extends Logic implements PayloadShapeMetadata {
  final String format;
  final String cloneFormat;

  _FormatSignal(this.format, this.cloneFormat, {super.name}) : super(width: 2);

  @override
  String get payloadShapeMetadata => format;

  @override
  _FormatSignal clone({String? name}) =>
      _FormatSignal(cloneFormat, cloneFormat, name: name ?? this.name);
}

class _FormatNet extends LogicNet implements PayloadShapeMetadata {
  final String format;
  final String cloneFormat;

  _FormatNet(this.format, this.cloneFormat, {super.name}) : super(width: 2);

  @override
  String get payloadShapeMetadata => format;

  @override
  _FormatNet clone({String? name}) =>
      _FormatNet(cloneFormat, cloneFormat, name: name ?? this.name);
}

class _ErasedStructure extends LogicStructure {
  _ErasedStructure({super.name}) : super([Logic(name: 'field')]);

  @override
  LogicStructure clone({String? name}) =>
      LogicStructure([Logic(name: 'field')], name: name);
}

class _ChangedFieldStructure extends LogicStructure {
  _ChangedFieldStructure({bool changed = false, super.name})
      : super([Logic(name: changed ? 'other' : 'field')]);

  @override
  _ChangedFieldStructure clone({String? name}) =>
      _ChangedFieldStructure(changed: true, name: name);
}

enum _CloneState { idle, busy }

class _MisclonedEnumStructure extends LogicStructure {
  _MisclonedEnumStructure({bool changed = false, super.name})
      : super([
          LogicEnum<_CloneState>.withMapping(
              changed
                  ? {_CloneState.idle: 1, _CloneState.busy: 0}
                  : {_CloneState.idle: 0, _CloneState.busy: 1},
              name: 'state')
        ]);

  @override
  _MisclonedEnumStructure clone({String? name}) =>
      _MisclonedEnumStructure(changed: true, name: name);
}

class _PreservingInputChild extends Module {
  Logic get result => output('result');
  Logic get fixedBits => output('fixedBits');

  _PreservingInputChild(Logic source) {
    final port = addTypedInput('source', source);
    final structure = port as _MixedConstantStructure;
    addOutput('result', width: 4) <= structure;
    addOutput('fixedBits', width: 2) <= structure.fixedBits;
  }
}

class _PreservingInputParent extends Module {
  _PreservingInputParent(Logic data) {
    data = addInput('data', data, width: 2);
    final source = _MixedConstantStructure(
      data,
      Const('xz', width: 2),
      name: 'source',
    );
    final child = _PreservingInputChild(source);
    addOutput('result', width: 4) <= child.result;
    addOutput('fixedBits', width: 2) <= child.fixedBits;
  }
}

class ModuleWithPartialAssignInlineAndOutReuseModule extends Module {
  ModuleWithPartialAssignInlineAndOutReuseModule(MyStruct inp) {
    inp = addTypedInput('inp', inp);
    final out = addTypedOutput('out', inp.clone);

    out.valid <= mux(inp.ready, inp.valid, Const(0));
    out.ready <= (~out.valid);
  }
}

class ParentModuleWithStructsContainingPorts extends Module {
  ParentModuleWithStructsContainingPorts(Logic x) {
    x = addInput('x', x);

    final child = ChildModuleForStructsOfPorts(
      x,
      LogicNet(name: 'y'),
    );

    LogicStructure(name: 'BADNAMEO2', [child.out2]) ^ x;
  }
}

class ChildModuleForStructsOfPorts extends Module {
  late final Logic out1 = addOutput('out1');
  late final Logic out2 = addTypedOutput('out2', out1.clone);
  ChildModuleForStructsOfPorts(Logic inp, LogicNet io) {
    inp = addTypedInput('inp', inp);
    io = addTypedInOut('io', io);

    out1 <= inp;
    out2 <= io;

    LogicStructure(name: 'BADNAMEI', [inp]) ^
        LogicStructure(name: 'BADNAMEIO', [io]);
    LogicStructure(name: 'BADNAMEO1', [out1]) ^ Const(1) ^ inp;
  }
}

class ParentModuleWithPackingSubModuleOutput extends Module {
  ParentModuleWithPackingSubModuleOutput(
    Logic x,
  ) {
    x = addInput('x', x);
    ChildModuleWithPackingOutput(x).myOut.packed.xor() ^ x;
  }
}

class ChildModuleWithPackingOutput extends Module {
  late final MyStruct myOut = addTypedOutput('myOut', MyStruct().clone);
  ChildModuleWithPackingOutput(Logic x) {
    x = addInput('x', x);
    x ^ myOut.packed.xor();
  }
}

class _MyStructInputConsumer extends Module {
  Logic get observed => output('observed');

  _MyStructInputConsumer(MyStruct pair, {required super.name})
      : super(definitionName: 'MyStructInputConsumer') {
    pair = addTypedInput('pair', pair);
    addOutput('observed', width: pair.width) <= pair;
  }
}

class _ScalarInputsToMyStructChild extends Module {
  _ScalarInputsToMyStructChild(Logic readyValue, Logic validValue)
      : super(definitionName: 'ScalarInputsToMyStructChild') {
    readyValue = addInput('readyValue', readyValue);
    validValue = addInput('validValue', validValue);
    final pair = MyStruct(name: 'pair');
    pair.ready <= readyValue;
    pair.valid <= validValue;
    final child = _MyStructInputConsumer(pair, name: 'consumer');
    addOutput('observed', width: pair.width) <= child.observed;
  }
}

class _MyStructOutputProducer extends Module {
  MyStruct get pair => output('pair') as MyStruct;

  _MyStructOutputProducer(
    Logic readyValue,
    Logic validValue, {
    required super.name,
  }) : super(definitionName: 'MyStructOutputProducer') {
    readyValue = addInput('readyValue', readyValue);
    validValue = addInput('validValue', validValue);
    final value = MyStruct(name: 'pairValue');
    value.ready <= readyValue;
    value.valid <= validValue;
    addTypedOutput('pair', value.clone).gets(value);
  }
}

class _MyStructChildToParentOutput extends Module {
  _MyStructChildToParentOutput(Logic readyValue, Logic validValue)
      : super(definitionName: 'MyStructChildToParentOutput') {
    readyValue = addInput('readyValue', readyValue);
    validValue = addInput('validValue', validValue);
    final child =
        _MyStructOutputProducer(readyValue, validValue, name: 'source');
    addTypedOutput('pair', child.pair.clone).gets(child.pair);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('ROHD payload shape helper coexists with downstream helper', () {
    final constant = LogicStructure([Const(1)]);
    final driveable = LogicStructure([Logic(name: 'field')]);
    expect(sameDeclaredPayloadShape(constant, driveable), isFalse);
    expect(sameRohdPayloadShape(constant, driveable), isFalse);
    expect(sameRohdPayloadShape(constant, driveable, ignoreConstantNames: true),
        isTrue);
    expect(
        sameRohdPayloadShape(
            _FormatSignal('first', 'first'), _FormatSignal('second', 'second')),
        isFalse);
  });

  test('payload sets compare declared formats across packed bridges', () {
    final first = _FormatSignal('first', 'first');
    final matching = _FormatSignal('first', 'first');
    final second = _FormatSignal('second', 'second');
    final bridge = Logic(width: 2);
    expect(rohdPayloadsCompatible([first, bridge, matching]), isTrue);
    expect(rohdPayloadsCompatible([first, bridge, second]), isFalse);
    expect(rohdPayloadsCompatible([bridge, first, second]), isFalse);
    expect(rohdPayloadsCompatible([first, Logic(width: 3)]), isFalse);
    final constant = LogicStructure([Const(1)]);
    final driveable = LogicStructure([Logic(name: 'field')]);
    expect(rohdPayloadsCompatible([constant, driveable]), isFalse);
    expect(
        rohdPayloadsCompatible([constant, driveable],
            ignoreConstantNames: true),
        isTrue);
  });

  test('typed clones and inputs reject nested semantic changes', () {
    final scalar = _FormatSignal('first', 'second', name: 'field');
    final nested = LogicStructure([scalar], name: 'nested');
    expect(scalar.cloneTyped, throwsA(isA<LogicConstructionException>()));
    expect(nested.cloneTyped, throwsA(isA<LogicConstructionException>()));
    final module = DummyModule();
    expect(() => module.addTypedInput<Logic>('dataIn', nested),
        throwsA(isA<PortTypeException>()));
    expect(module.inputs, isEmpty);
    expect(_MisclonedEnumStructure().cloneTyped,
        throwsA(isA<LogicConstructionException>()));
    expect(() => module.addTypedInput('stateIn', _MisclonedEnumStructure()),
        throwsA(isA<PortTypeException>()));

    final Logic erased = _ErasedStructure();
    expect(erased.cloneTyped, throwsA(isA<LogicConstructionException>()));
    expect(() => module.addTypedInput('erased', erased),
        throwsA(isA<PortTypeException>()));

    final valid = _FormatSignal('first', 'first');
    expect(valid.cloneTyped().payloadShapeMetadata, 'first');
    expect(
        module.addTypedInput('validData', valid).payloadShapeMetadata, 'first');
  });

  test('typed inouts reject semantic changes before registering ports', () {
    final net = _FormatNet('first', 'second');
    final module = DummyModule();
    expect(() => module.addTypedInOut<Logic>('io', net),
        throwsA(isA<PortTypeException>()));
    expect(module.inOuts, isEmpty);
    final valid = _FormatNet('first', 'first');
    expect(module.addTypedInOut<Logic>('io', valid), isA<_FormatNet>());
  });

  test('typed clones reject nested declared type erasure', () {
    final nested = LogicStructure([_ErasedStructure(name: 'member')]);
    final rawClone = nested.clone();
    expect(sameRohdPayloadShape(nested, rawClone), isTrue);
    expect(nested.cloneTyped, throwsA(isA<LogicConstructionException>()));
    expect(() => DummyModule().addTypedInput('dataIn', nested),
        throwsA(isA<PortTypeException>()));

    var changed = false;
    final array = TypedLogicArray<Logic, LogicValue>(
      [2],
      ({name}) => changed
          ? LogicStructure([Logic(name: 'field')], name: name)
          : _ErasedStructure(name: name),
    );
    changed = true;
    expect(array.cloneTyped, throwsA(isA<LogicConstructionException>()));
    expect(() => DummyModule().addTypedInput('arrayIn', array),
        throwsA(isA<PortTypeException>()));
  });

  test('typed clones reject unrelated field name changes', () {
    final source = _ChangedFieldStructure(name: 'source');
    expect(() => source.cloneTyped(name: 'renamed'),
        throwsA(isA<LogicConstructionException>()));
    expect(() => DummyModule().addTypedInput('dataIn', source),
        throwsA(isA<PortTypeException>()));
  });

  test('typed array clones reject changed element formats', () {
    var changed = false;
    final array = TypedLogicArray<_FormatSignal, LogicValue>(
        [2],
        ({name}) => _FormatSignal(
            changed ? 'second' : 'first', changed ? 'second' : 'first',
            name: name));
    changed = true;
    expect(array.cloneTyped, throwsA(isA<LogicConstructionException>()));
    expect(() => DummyModule().addTypedInput('dataIn', array),
        throwsA(isA<PortTypeException>()));
  });

  test('simple struct module', () async {
    final mod = SimpleStructModuleContainer(Logic(), Logic());
    await mod.build();

    final sv = mod.dumpSystemVerilog();

    expect(sv, isNot(contains('internal_struct')));

    expect(sv, contains('input logic [1:0] myIn'));
    expect(sv, contains('output logic [1:0] myOut'));

    final vectors = [
      Vector({'a1': 0, 'a2': 1}, {'b1': 1, 'b2': 0}),
      Vector({'a1': 1, 'a2': 0}, {'b1': 0, 'b2': 1}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('typed array is an array', () async {
    final mod = MatcherPassThrough(LogicArray([4], 2));
    await mod.build();

    expect(mod.anyOut, isA<LogicArray>());

    final sv = mod.dumpSystemVerilog();

    expect(sv, contains('input logic [3:0][1:0] anyIn'));
    expect(sv, contains('output logic [3:0][1:0] anyOut'));
    expect(sv, contains('assign anyOut = anyIn;'));
  });

  test('module with inline partial assignment and output reuse', () async {
    final mod = ModuleWithPartialAssignInlineAndOutReuseModule(MyStruct());
    await mod.build();

    final vectors = [
      Vector({'inp': '00'}, {'out': '01'}),
      Vector({'inp': '10'}, {'out': '01'}),
      Vector({'inp': '01'}, {'out': '01'}),
      Vector({'inp': '11'}, {'out': '10'}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('structure containing ports naming properly', () async {
    final mod = ParentModuleWithStructsContainingPorts(Logic());
    await mod.build();

    final sv = mod.dumpSystemVerilog();

    // if naming is wrong, these names will appear in the SV in ports
    expect(
        sv, isNot(contains(RegExp(r'\b(?:input|output|inout)\s+.*BADNAME'))));

    // if name is renamed/uniquified, it won't be an exact match
    expect(
        sv, contains(RegExp(r'^\s*input logic inp[,\s]*$', multiLine: true)));
    expect(
        sv, contains(RegExp(r'^\s*output logic out1[,\s]*$', multiLine: true)));
    expect(
        sv, contains(RegExp(r'^\s*output logic out2[,\s]*$', multiLine: true)));
    expect(sv, contains(RegExp(r'^\s*inout wire io[,\s]*$', multiLine: true)));
  });

  test('packed struct output inside and outside of module', () async {
    final mod = ParentModuleWithPackingSubModuleOutput(Logic());

    // just building will detect if there was a bad reuse of packed
    await mod.build();
  });

  test('structure fields pack into aggregate child inputs', () async {
    final mod = _ScalarInputsToMyStructChild(Logic(), Logic());
    await mod.build();

    final vectors = [
      Vector({'readyValue': 0, 'validValue': 0}, {'observed': 0}),
      Vector({'readyValue': 1, 'validValue': 0}, {'observed': 1}),
      Vector({'readyValue': 0, 'validValue': 1}, {'observed': 2}),
      Vector({'readyValue': 1, 'validValue': 1}, {'observed': 3}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('aggregate structure child outputs pack through parent outputs',
      () async {
    final mod = _MyStructChildToParentOutput(Logic(), Logic());
    await mod.build();

    final vectors = [
      Vector({'readyValue': 0, 'validValue': 0}, {'pair': 0}),
      Vector({'readyValue': 1, 'validValue': 0}, {'pair': 1}),
      Vector({'readyValue': 0, 'validValue': 1}, {'pair': 2}),
      Vector({'readyValue': 1, 'validValue': 1}, {'pair': 3}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('const typed ports', () {
    final typedPortCreators = {
      'input': <LogicType extends Logic>(LogicType logic) =>
          DummyModule().addTypedInput<LogicType>('p', logic),
      'output': <LogicType extends Logic>(LogicType logic) => DummyModule()
          .addTypedOutput<LogicType>(
              'p', logic.clone as LogicType Function({String name})),
      'inOut': <LogicType extends Logic>(LogicType logic) =>
          DummyModule().addTypedInOut<LogicType>('p', logic),
    };

    for (final MapEntry(key: portType, value: creator)
        in typedPortCreators.entries) {
      test('$portType with const', () {
        expect(
          () => creator(Const(1)),
          throwsA(isA<PortTypeException>()),
        );
      });

      test('$portType with const but param as Logic', () {
        var failed = false;
        try {
          creator<Logic>(Const(1));
        } on PortTypeException {
          failed = true;
        }

        expect(failed, portType == 'inOut');
      });

      test('$portType with struct containing const', () {
        expect(
          () => creator(StructWithConst()),
          throwsA(isA<PortTypeException>()),
        );
      });

      test('$portType with struct containing const but param as Logic', () {
        var failed = false;
        try {
          creator<Logic>(StructWithConst());
        } on PortTypeException {
          failed = true;
        }

        expect(failed, portType == 'inOut' || portType == 'input');
      });
    }

    test('input with const structure and driveable clone', () {
      final source = StructWithConstAndDriveableClone.constant();
      final input = DummyModule().addTypedInput('p', source);

      expect(input, isA<StructWithConstAndDriveableClone>());
      expect(input.hasConsts, isFalse);
      expect(input.data.value, LogicValue.one);
    });
  });

  group('structure-preserving typed inputs', () {
    test('preserves by default and supports explicit flattening', () {
      final source = StructWithConstAndDriveableClone.constant();
      final flattened = DummyModule().addTypedInput<Logic>('p', source,
          preserveStructuredConstants: false);
      final module = DummyModule();
      final preserved = module.addTypedInput<Logic>('p', source);

      expect(flattened, isNot(isA<LogicStructure>()));
      expect(preserved, isA<StructWithConstAndDriveableClone>());
      expect((preserved as LogicStructure).hasConsts, isFalse);
      expect(preserved.value, LogicValue.one);
      expect(module.input('p'), same(preserved));
      expect(module.inputSource('p'), same(source));
      final typed = DummyModule().addTypedInput('p', source);
      expect(typed, isA<StructWithConstAndDriveableClone>());
    });

    test('retains existing behavior for ordinary inputs and scalar constants',
        () {
      final signal = Logic(width: 2);
      final signalModule = DummyModule();
      final signalPort = signalModule.addTypedInput('p', signal);
      expect(signalPort.width, 2);
      expect(signalModule.inputSource('p'), same(signal));

      final structure = MyStruct();
      final preserved = DummyModule().addTypedInput<Logic>('p', structure);
      expect(preserved, isA<MyStruct>());

      final scalar = DummyModule().addTypedInput<Logic>('p', Const(1));
      expect(scalar, isNot(isA<Const>()));
      expect(scalar.value, LogicValue.one);
      expect(
        () => DummyModule().addTypedInput('p', Const(1)),
        throwsA(isA<PortTypeException>()),
      );
    });

    test('rejects constant-containing clones that are not driveable', () {
      expect(
        () => DummyModule().addTypedInput<Logic>('p', StructWithConst()),
        throwsA(isA<PortTypeException>()),
      );
      expect(
        () => DummyModule()
            .addTypedInput<Logic>('p', _ConstWithNetClone(Const(1))),
        throwsA(isA<PortTypeException>()),
      );
    });

    test('rejects constant-containing structures with nets', () {
      final source = LogicStructure([Const(1), LogicNet()]);
      expect(
        () => DummyModule().addTypedInput<Logic>('p', source),
        throwsA(isA<PortTypeException>()),
      );
    });

    test('preserves mixed constant fields through a child with X and Z',
        () async {
      final module = _PreservingInputParent(Logic(width: 2));
      await module.build();
      final vectors = [
        Vector({'data': '00'}, {'result': 'xz00', 'fixedBits': 'xz'}),
        Vector({'data': '11'}, {'result': 'xz11', 'fixedBits': 'xz'}),
        Vector({'data': 'zx'}, {'result': 'xzzx', 'fixedBits': 'xz'}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);
    });
  });

  group('simple struct module with nets', () {
    Future<Module> makeMod() async {
      final mod =
          SimpleStructModuleContainer(LogicNet(), LogicNet(), asNet: true);
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      expect(sv, isNot(contains('internal_struct')));

      expect(sv, contains('inout wire [1:0] myIn'));
      expect(sv, contains('inout wire [1:0] myOut'));

      return mod;
    }

    test('forward', () async {
      final mod = await makeMod();

      final vectors = [
        Vector({'a1': 0, 'a2': 1}, {'b1': 1, 'b2': 0}),
        Vector({'a1': 1, 'a2': 0}, {'b1': 0, 'b2': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('reversed', () async {
      final mod = await makeMod();

      final vectorsReversed = [
        Vector({'b1': 1, 'b2': 0}, {'a1': 0, 'a2': 1}),
        Vector({'b1': 0, 'b2': 1}, {'a1': 1, 'a2': 0}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsReversed);
      SimCompare.checkIverilogVector(mod, vectorsReversed);
    });
  });

  group('illegal match port creations', () {
    final typedPortCreators = {
      'input': (Logic logic) => DummyModule().addTypedInput('p', logic),
      'output': (Logic logic) => DummyModule().addTypedOutput('p', logic.clone),
      'inOut': (Logic logic) => DummyModule().addTypedInOut('p', logic),
    };

    group('struct with partial nets fails', () {
      for (final MapEntry(key: portType, value: creator)
          in typedPortCreators.entries) {
        test(portType, () {
          expect(
            () => creator(LogicStructure([Logic(), LogicNet()])),
            throwsA(isA<PortTypeException>()),
          );
        });
      }
    });

    group('struct with missing clone name fails', () {
      for (final MapEntry(key: portType, value: creator)
          in typedPortCreators.entries) {
        test(portType, () {
          try {
            creator(CloneNoNameStruct(asNet: portType == 'inOut'));
          } on PortTypeException catch (e) {
            expect(e.message, contains('failed to update the signal name'));
          }
        });
      }
    });
  });

  test('partial net struct assign', () async {
    final mod = PartialLogicNetStructAssignment(MyStruct(asNet: true));
    await mod.build();

    final vectors = [
      Vector({'a': 0}, {'b': '0z'}),
      Vector({'a': 3}, {'b': '1z'})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('various port types to match', () {
    final portTypes = [
      (name: 'simple logic', maker: () => Logic(width: 8)),
      (name: 'logic array', maker: () => LogicArray([4], 2)),
      (name: 'deeper logic array', maker: () => LogicArray([1, 2, 2], 2)),
      (
        name: 'fancy mixed struct',
        maker: () => LogicStructure([
              Logic(width: 2),
              LogicArray([2], 2),
              LogicStructure([Logic(), Logic()])
            ])
      ),
      (name: 'logic net', maker: () => LogicNet(width: 8)),
      (name: 'logic array net', maker: () => LogicArray.net([2], 4)),
      (
        name: 'fancy logic struct net',
        maker: () => LogicStructure([
              LogicNet(),
              LogicNet(),
              LogicArray.net([4], 1),
              LogicStructure([LogicNet(width: 2)])
            ])
      ),
    ];

    final modMakers = [
      (name: 'basic', maker: MatcherModule.new, invert: true),
      (name: 'wrapper', maker: MatcherModuleWrapper.new, invert: true),
      (name: 'pass through', maker: MatcherPassThrough.new, invert: false),
    ];

    for (final modMaker in modMakers) {
      group('${modMaker.name} module', () {
        for (final portType in portTypes) {
          test(portType.name, () async {
            final mod = modMaker.maker(portType.maker());

            // check that things cloned up properly
            expect(mod.anyOut.runtimeType, portType.maker().runtimeType);

            await mod.build();

            final vectors = [
              Vector(
                  {'anyIn': 0xa5}, {'anyOut': modMaker.invert ? 0x5a : 0xa5}),
              Vector(
                  {'anyIn': 0xff}, {'anyOut': modMaker.invert ? 0x00 : 0xff}),
              Vector(
                  {'anyIn': 0x13}, {'anyOut': modMaker.invert ? 0xec : 0x13}),
            ];

            await SimCompare.checkFunctionalVector(mod, vectors);
            SimCompare.checkIverilogVector(mod, vectors);
          });
        }
      });
    }
  });

  test('single bit struct port partial assignment', () async {
    final mod = ModuleWithOneBitStructPort(OneBitStruct());
    await mod.build();

    final sv = mod.dumpSystemVerilog();

    // no slicing on single-bit signals
    expect(sv, contains('assign outStruct = outStruct_oneBit'));

    final vectors = [
      Vector({'inStruct': 0}, {'outStruct': 0}),
      Vector({'inStruct': 1}, {'outStruct': 1}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}

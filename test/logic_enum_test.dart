// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_enum_test.dart
// Tests for LogicEnum.
//
// 2026 July 22
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum TestEnum { a, b, c }

enum SingleValueEnum { only }

enum OtherEnum { a, b, c }

class MyListLogicEnum extends LogicEnum<TestEnum> {
  MyListLogicEnum({super.name, super.naming}) : super(TestEnum.values);

  @override
  MyListLogicEnum clone({String? name}) => MyListLogicEnum(
        name: name ?? this.name,
        naming: Naming.chooseCloneNaming(
          originalName: this.name,
          newName: name,
          originalNaming: naming,
          newNaming: null,
        ),
      );
}

class MyMapLogicEnum extends LogicEnum<TestEnum> {
  MyMapLogicEnum({super.name, super.naming})
      : super.withMapping({
          TestEnum.a: 1,
          // TestEnum.b: 5, // `b` is not mapped!
          TestEnum.c: 7,
        }, width: 3);

  @override
  MyMapLogicEnum clone({String? name}) => MyMapLogicEnum(
        name: name ?? this.name,
        naming: Naming.chooseCloneNaming(
          originalName: this.name,
          newName: name,
          originalNaming: naming,
          newNaming: null,
        ),
      );
}

class SimpleModWithEnum extends Module {
  SimpleModWithEnum(Logic carrot) {
    carrot = addInput('carrot', carrot, width: 3);
    final e = MyMapLogicEnum(name: 'elephant');
    addOutput('banana', width: 3) <= carrot & e;
  }
}

class ConflictingEnumMod extends Module {
  ConflictingEnumMod(Logic carrot) {
    carrot = addInput('carrot', carrot, width: 3);
    final e1 = MyListLogicEnum(name: 'elephantList');
    final e2 = MyMapLogicEnum(name: 'elephantMap');

    addOutput('banana', width: 3) <= carrot & (e1.zeroExtend(3) ^ e2);
  }
}

class ModWithEnumConstAssignment extends Module {
  ModWithEnumConstAssignment(Logic carrot) {
    carrot = addInput('carrot', carrot, width: 2);
    final e = MyListLogicEnum(name: 'elephant')..getsEnum(TestEnum.b);
    addOutput('banana', width: 2) <= carrot & e;
  }
}

class SharedEnumConstantModule extends Module {
  SharedEnumConstantModule(Logic select,
      {required bool directAssignments, Logic? clock}) {
    select = addInput('select', select);
    final first = addTypedOutput('first', LogicEnum(TestEnum.values).clone);
    final second = addTypedOutput('second', LogicEnum(OtherEnum.values).clone);
    final raw = addOutput('raw', width: 2);
    final zero = Const(0, width: 2);
    final conditionals = [
      If(select, then: [
        if (directAssignments) ConditionalAssign(first, zero) else first < zero,
        if (directAssignments)
          ConditionalAssign(second, zero)
        else
          second < zero,
        raw < zero,
      ], orElse: [
        first < 1,
        second < 1,
        raw < 1
      ]),
    ];
    if (clock == null) {
      Combinational(conditionals);
    } else {
      Sequential(addInput('clock', clock), conditionals);
    }
  }
}

class PairedEnumConstantModule extends Module with SystemVerilog {
  PairedEnumConstantModule(Logic source) {
    final firstInput = addInput('firstInput', source, width: 2);
    final secondInput = addInput('secondInput', source, width: 2);
    final rawInput = addInput('rawInput', source, width: 2);
    final first = addTypedOutput('first', LogicEnum(TestEnum.values).clone);
    final second = addTypedOutput('second', LogicEnum(OtherEnum.values).clone);
    final raw = addOutput('raw', width: 2);
    first <= firstInput;
    second <= secondInput;
    raw <= rawInput;
    portTypePairs.addAll({firstInput: first, secondInput: second});
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
          Map<String, String> ports) =>
      'assign ${ports['first']} = ${ports['firstInput']};\n'
      'assign ${ports['second']} = ${ports['secondInput']};\n'
      'assign ${ports['raw']} = ${ports['rawInput']};';
}

class SharedConstantFanoutModule extends Module {
  final source = Const(1, width: 2);

  SharedConstantFanoutModule({required bool pairedModule}) {
    if (pairedModule) {
      final child = PairedEnumConstantModule(source);
      for (final name in ['first', 'second', 'raw']) {
        addOutput(name, width: 2) <= child.output(name);
      }
    } else {
      final first = LogicEnum(TestEnum.values)..gets(source);
      final second = LogicEnum(OtherEnum.values)..gets(source);
      addOutput('first', width: 2) <= first;
      addOutput('second', width: 2) <= second;
      addOutput('raw', width: 2) <= source;
    }
  }
}

class SharedLiveFanoutModule extends Module {
  SharedLiveFanoutModule(Logic source) {
    source = addInput('source', source, width: 2);
    final child = PairedEnumConstantModule(source);
    for (final name in ['first', 'second', 'raw']) {
      addOutput(name, width: 2) <= child.output(name);
    }
  }
}

class SharedConstantInstancesModule extends Module {
  SharedConstantInstancesModule() {
    final constant = Const(1, width: 2);
    final alias = Logic(name: 'alias', width: 2)..gets(constant);
    final first = PairedEnumConstantModule(constant);
    final second = PairedEnumConstantModule(alias);
    addOutput('first', width: 2) <= first.output('first');
    addOutput('second', width: 2) <= second.output('second');
    addOutput('raw', width: 2) <= alias;
  }
}

class ModWithCaseAndEnumCondAssign extends Module {
  ModWithCaseAndEnumCondAssign(Logic durian) {
    durian = addInput('durian', durian);

    final currState = MyListLogicEnum(name: 'currState');
    final nextState = MyListLogicEnum(name: 'nextState');

    nextState <=
        cases(
            currState,
            {
              0: 0,
              MyListLogicEnum()..getsEnum(TestEnum.b): MyListLogicEnum()
                ..getsEnum(TestEnum.b),
              TestEnum.c: 2,
            },
            width: 2);

    addOutput('pineapple') <= durian & nextState.xor();
  }
}

class EnumNameCollisionModule extends Module {
  EnumNameCollisionModule() {
    final enumSignal = MyListLogicEnum(name: 'a');
    addOutput('TestEnum', width: enumSignal.width) <= enumSignal;
    addOutput('a');
  }
}

class EnumCasesModule extends Module {
  late final Logic selected;
  late final LogicEnum<TestEnum> result;

  EnumCasesModule(Logic selector) {
    selector = addInput('selector', selector, width: 2);
    final enumSelector = MyListLogicEnum(name: 'enumSelector')..gets(selector);
    LogicEnum<TestEnum> enumValue(TestEnum value) =>
        MyListLogicEnum()..getsEnum(value);
    selected = cases(enumSelector, {
      TestEnum.a: enumValue(TestEnum.b),
      TestEnum.b: enumValue(TestEnum.c),
      TestEnum.c: enumValue(TestEnum.a),
    });
    result = MyListLogicEnum(name: 'result')..gets(selected);
    addOutput('result', width: 2) <= result;
  }
}

class EnumSubsetAssignmentModule extends Module {
  EnumSubsetAssignmentModule(Logic selector) {
    selector = addInput('selector', selector, width: 2);
    final narrow = LogicEnum<TestEnum>.withMapping(
      {
        TestEnum.a: 0,
        TestEnum.b: 1,
      },
      width: 2,
      name: 'narrow',
      naming: Naming.reserved,
      definitionName: 'NarrowEnum',
    )..gets(selector);
    final broad = LogicEnum(
      TestEnum.values,
      width: 2,
      name: 'broad',
      naming: Naming.reserved,
      definitionName: 'BroadEnum',
    )..gets(narrow);

    addOutput('result', width: 2) <= broad;
  }
}

class EnumSubsetConditionalAssignmentModule extends Module {
  EnumSubsetConditionalAssignmentModule(Logic selector) {
    selector = addInput('selector', selector, width: 2);
    final narrow = LogicEnum<TestEnum>.withMapping(
      {
        TestEnum.a: 0,
        TestEnum.b: 1,
      },
      width: 2,
      name: 'narrow',
      naming: Naming.reserved,
      definitionName: 'NarrowEnum',
    )..gets(selector);
    final broad = LogicEnum(
      TestEnum.values,
      width: 2,
      name: 'broad',
      naming: Naming.reserved,
      definitionName: 'BroadEnum',
    );

    Combinational([broad < narrow]);
    addOutput('result', width: 2) <= broad;
  }
}

class EnumFromSliceModule extends Module {
  EnumFromSliceModule(Logic source) {
    source = addInput('source', source, width: 8);
    final slicedEnum = MyListLogicEnum(
      name: 'slicedEnum',
      naming: Naming.reserved,
    )..gets(source.getRange(2, 4));

    addOutput('result', width: slicedEnum.width) <= slicedEnum;
  }
}

class EnumFromAssignedBitsModule extends Module {
  EnumFromAssignedBitsModule(Logic source) {
    source = addInput('source', source, width: 2);
    final state = MyListLogicEnum(
      name: 'state',
      naming: Naming.reserved,
    );
    for (var index = 0; index < state.width; index++) {
      state.assignSubset([source[index]], start: index);
    }

    addOutput('result', width: state.width) <= state;
  }
}

class PartiallyAssignedEnumModule extends Module {
  PartiallyAssignedEnumModule(Logic source) {
    source = addInput('source', source);
    final state = MyListLogicEnum(
      name: 'state',
      naming: Naming.reserved,
    )..assignSubset([source]);

    addOutput('result', width: state.width) <= state;
  }
}

class SingleValueEnumModule extends Module {
  SingleValueEnumModule() {
    final state = LogicEnum(
      SingleValueEnum.values,
      name: 'state',
      naming: Naming.reserved,
      definitionName: 'SingleState',
    )..getsEnum(SingleValueEnum.only);

    addOutput('result', width: state.width) <= state;
  }
}

class WideSparseEnumModule extends Module {
  static final wideValue = BigInt.one << 80;

  WideSparseEnumModule() {
    final state = LogicEnum<TestEnum>.withMapping(
      {
        TestEnum.a: BigInt.zero,
        TestEnum.c: wideValue,
      },
      name: 'state',
      naming: Naming.reserved,
      definitionName: 'WideSparseState',
    )..getsEnum(TestEnum.c);

    addOutput('result', width: state.width) <= state;
  }
}

class EnumPacket extends LogicStructure {
  final MyListLogicEnum state;
  final Logic payload;

  factory EnumPacket({String name = 'packet'}) => EnumPacket._(
        MyListLogicEnum(name: 'state'),
        Logic(width: 2, name: 'payload'),
        name: name,
      );

  EnumPacket._(this.state, this.payload, {required super.name})
      : super([state, payload]);

  @override
  EnumPacket clone({String? name}) => EnumPacket(name: name ?? this.name);
}

class EnumStructureModule extends Module {
  EnumStructureModule(Logic source) {
    source = addInput('source', source, width: 4);
    final packet = EnumPacket()..gets(source);

    addOutput('stateResult', width: packet.state.width) <= packet.state;
    addOutput('packedResult', width: packet.width) <= packet.packed;
    addOutput('rangeResult', width: packet.state.width) <=
        packet.getRange(0, packet.state.width);
  }
}

class EnumArrayBoundaryModule extends Module {
  EnumArrayBoundaryModule(Logic source) {
    source = addInput('source', source, width: 4);
    final lanes = LogicArray(
      [2],
      2,
      name: 'lanes',
      numUnpackedDimensions: 1,
    )..gets(source);
    final state = MyListLogicEnum(
      name: 'state',
      naming: Naming.reserved,
    )..gets(lanes.elements[1]);

    addOutput('stateResult', width: state.width) <= state;
    addOutput('packedResult', width: lanes.width) <= lanes.packed;
  }
}

class EnumHierarchyChild extends Module {
  Logic get result => output('result');

  EnumHierarchyChild(Logic source) : super(name: 'enumHierarchyChild') {
    source = addInput('source', source, width: 2);
    final narrow = LogicEnum<TestEnum>.withMapping(
      {
        TestEnum.a: 0,
        TestEnum.b: 1,
      },
      width: 2,
      name: 'narrow',
      naming: Naming.reserved,
      definitionName: 'ChildNarrowEnum',
    )..gets(source);

    addOutput('result', width: narrow.width) <= narrow;
  }
}

class EnumHierarchyModule extends Module {
  EnumHierarchyModule(Logic source) {
    source = addInput('source', source, width: 2);
    final child = EnumHierarchyChild(source);
    final broad = LogicEnum(
      TestEnum.values,
      width: 2,
      name: 'broad',
      naming: Naming.reserved,
      definitionName: 'ParentBroadEnum',
    )..gets(child.result);

    addOutput('result', width: broad.width) <= broad;
  }
}

class TypedEnumPortsModule extends Module {
  late final LogicEnum<TestEnum> stateIn;
  late final LogicEnum<TestEnum> stateOut;

  TypedEnumPortsModule(LogicEnum<TestEnum> source)
      : super(name: 'typedEnumPorts') {
    stateIn = addTypedInput('stateIn', source);
    stateOut = addTypedOutput('stateOut', stateIn.clone)..gets(stateIn);
  }
}

class TypedEnumPartialSourceModule extends Module {
  TypedEnumPartialSourceModule(LogicEnum<TestEnum> source) {
    final stateIn = addTypedInput('stateIn', source);
    final packedValue = Logic(
      width: 3,
      name: 'packedValue',
      naming: Naming.reserved,
    )
      ..assignSubset([Const(0)])
      ..assignSubset([stateIn], start: 1)
      ..assignSubset([Const(0)], start: 2);

    addOutput('result', width: packedValue.width) <= packedValue;
  }
}

class TypedEnumRangeDestinationModule extends Module {
  TypedEnumRangeDestinationModule(Logic source, LogicEnum<TestEnum> type) {
    source = addInput('source', source, width: type.width);
    final stateOut = addTypedOutput('stateOut', type.clone);
    for (var index = 0; index < stateOut.width; index++) {
      stateOut.assignSubset([source[index]], start: index);
    }
  }
}

class TypedEnumHierarchyModule extends Module {
  late final TypedEnumPortsModule child;

  TypedEnumHierarchyModule(Logic source) {
    source = addInput('source', source, width: 2);
    final narrow = LogicEnum<TestEnum>.withMapping(
      {
        TestEnum.a: 0,
        TestEnum.c: 2,
      },
      width: 2,
      name: 'narrow',
      naming: Naming.reserved,
      definitionName: 'TypedChildNarrowEnum',
    )..gets(source);
    child = TypedEnumPortsModule(narrow);
    final broad = LogicEnum(
      TestEnum.values,
      width: 2,
      name: 'broad',
      naming: Naming.reserved,
      definitionName: 'ParentTypedBroadEnum',
    )..gets(child.stateOut);

    addOutput('result', width: broad.width) <= broad;
  }
}

class TypedEnumCasesModule extends Module {
  late final LogicEnum<TestEnum> stateIn;
  late final LogicEnum<TestEnum> stateOut;

  TypedEnumCasesModule(LogicEnum<TestEnum> source)
      : super(name: 'typedEnumCases') {
    stateIn = addTypedInput('stateIn', source);
    LogicEnum<TestEnum> enumValue(TestEnum value) =>
        stateIn.clone()..getsEnum(value);
    final selected = cases(stateIn, {
      TestEnum.a: enumValue(TestEnum.c),
      TestEnum.c: enumValue(TestEnum.a),
    });
    stateOut = addTypedOutput('stateOut', stateIn.clone)..gets(selected);
  }
}

class TypedEnumPortNameCollisionModule extends Module {
  TypedEnumPortNameCollisionModule(LogicEnum<TestEnum> source) {
    final stateIn = addTypedInput('stateIn', source);
    final stateInEnum = Logic(
      width: stateIn.width,
      name: 'stateIn_enum',
      naming: Naming.reserved,
    )..gets(stateIn);

    addOutput('result', width: stateIn.width) <= stateInEnum;
  }
}

class TypedEnumConsumersModule extends Module {
  late final TypedEnumPortsModule child;

  TypedEnumConsumersModule(LogicEnum<TestEnum> source) {
    final stateIn = addTypedInput('stateIn', source);
    child = TypedEnumPortsModule(stateIn);

    addOutput('inlineResult', width: stateIn.width) <=
        stateIn ^ Const(1, width: stateIn.width);
    addOutput('childResult', width: stateIn.width) <= child.stateOut;
  }
}

class EnumIfElseModule extends Module {
  EnumIfElseModule(Logic source, Logic select) {
    source = addInput('source', source, width: 2);
    select = addInput('select', select);
    final narrow = LogicEnum<TestEnum>.withMapping(
      {
        TestEnum.a: 0,
        TestEnum.b: 1,
      },
      width: 2,
      name: 'narrow',
      definitionName: 'IfNarrowEnum',
    )..gets(source);
    final broad = LogicEnum(
      TestEnum.values,
      width: 2,
      name: 'broad',
      definitionName: 'IfBroadEnum',
    );

    Combinational([
      If(select, then: [broad < narrow], orElse: [broad < TestEnum.c])
    ]);
    addOutput('result', width: broad.width) <= broad;
  }
}

class EmptyModule extends Module {}

Future<void> checkEnumModeParity(Module module, List<Vector> vectors) async {
  await module.build();
  await SimCompare.checkFunctionalVector(module, vectors);

  final typedSv = module.dumpSystemVerilog();
  expect(typedSv, contains('typedef enum'));
  SimCompare.checkIverilogVector(module, vectors);

  const configuration =
      SystemVerilogSynthesizerConfiguration(generateEnums: false);
  final untypedSv = module.dumpSystemVerilog(configuration: configuration);
  expect(untypedSv, isNot(contains('typedef enum')));
  expect(untypedSv, isNot(matches(RegExp(r"[A-Za-z_]\w*'\("))));
  SimCompare.checkIverilogVector(
    module,
    vectors,
    synthesizerConfiguration: configuration,
  );
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('enum populates based on list of values', () {
    final e = MyListLogicEnum();

    expect(e.mapping.length, TestEnum.values.length);
    expect(e.width, 2);

    var idx = 0;
    for (final val in TestEnum.values) {
      expect(e.mapping.containsKey(val), isTrue);
      expect(e.mapping[val]!.width, e.width);
      expect(e.mapping[val]!.toInt(), idx++);
    }
  });

  test('single-value enum has a one-bit representation', () {
    final logicEnum = LogicEnum(SingleValueEnum.values);

    expect(logicEnum.width, 1);
    expect(logicEnum.mapping[SingleValueEnum.only], LogicValue.zero);
  });

  test('empty enum mapping is rejected', () {
    expect(
      () => LogicEnum<TestEnum>.withMapping({}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('assignment between incompatible enum mappings is rejected', () {
    final destination = LogicEnum(TestEnum.values);
    final source = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 0,
      TestEnum.b: 2,
      TestEnum.c: 3,
    });

    expect(() => destination.gets(source), throwsA(isA<ArgumentError>()));
  });

  test('assignment from an enum subset to a superset is accepted', () {
    final broad = LogicEnum(TestEnum.values, width: 2);
    final broadConditional = LogicEnum(TestEnum.values, width: 2);
    final narrow = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 0,
      TestEnum.b: 1,
    }, width: 2);
    final conflicting = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 1,
      TestEnum.b: 0,
    }, width: 2);

    expect(() => broad.gets(narrow), returnsNormally);
    expect(broadConditional < narrow, isA<Conditional>());
    expect(() => narrow.gets(broad), throwsA(isA<ArgumentError>()));
    expect(() => broad.gets(conflicting), throwsA(isA<ArgumentError>()));
  });

  test('mapping width is inferred from integer encodings', () {
    final logicEnum = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 1,
      TestEnum.c: 7,
    });
    final wideValue = BigInt.one << 80;
    final wideEnum = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: BigInt.zero,
      TestEnum.c: wideValue,
    });

    expect(logicEnum.width, 3);
    expect(wideEnum.width, 81);
    expect(wideEnum.mapping[TestEnum.c]!.toBigInt(), wideValue);
  });

  test('clone follows standard Logic naming policy', () {
    final original = LogicEnum(
      TestEnum.values,
      name: 'state',
      naming: Naming.reserved,
    );

    final clone = original.clone();
    final renamedClone = original.clone(name: 'nextState');

    expect(clone.name, original.name);
    expect(clone.naming, Naming.mergeable);
    expect(renamedClone.name, 'nextState');
    expect(renamedClone.naming, Naming.renameable);
  });

  test('invalid mapping encodings are rejected', () {
    expect(
      () => LogicEnum<TestEnum>.withMapping({TestEnum.a: -1}),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => LogicEnum<TestEnum>.withMapping({TestEnum.a: 4}, width: 2),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('duplicate, invalid, and negative mapping values are rejected', () {
    expect(
      () => LogicEnum<TestEnum>.withMapping({
        TestEnum.a: 0,
        TestEnum.b: 0,
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => LogicEnum<TestEnum>.withMapping({
        TestEnum.a: 0,
        TestEnum.b: '0',
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => LogicEnum<TestEnum>.withMapping({TestEnum.a: 'x'}),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => LogicEnum<TestEnum>.withMapping({TestEnum.a: -BigInt.one}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('mixed mapping representations contribute to inferred width', () {
    final logicEnum = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: '10101',
      TestEnum.b: [
        LogicValue.one,
        LogicValue.zero,
        LogicValue.one,
        LogicValue.zero,
      ],
      TestEnum.c: 0,
    });

    expect(logicEnum.width, 5);
    expect(logicEnum.mapping[TestEnum.a]!.toInt(), 0x15);
    expect(logicEnum.mapping[TestEnum.b]!.width, 5);
  });

  test('sparse enum mutation APIs reject missing members and fill', () {
    final sparse = LogicEnum<TestEnum>.withMapping({TestEnum.a: 0}, width: 2);

    expect(() => sparse.getsEnum(TestEnum.b), throwsA(isA<ArgumentError>()));
    expect(() => sparse.put(TestEnum.b), throwsA(isA<ArgumentError>()));
    expect(() => sparse.inject(TestEnum.b), throwsA(isA<ArgumentError>()));
    expect(
      () => sparse.put(TestEnum.a, fill: true),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => sparse.inject(TestEnum.a, fill: true),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => sparse.gets(Const(1, width: sparse.width)),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('raw four-state values and raw conditional sources remain supported',
      () {
    final floatingEnum = MyListLogicEnum()..put(LogicValue.ofString('zz'));
    expect(floatingEnum.value, LogicValue.ofString('zz'));

    final invalidEnum = MyListLogicEnum()..put(LogicValue.ofString('x1'));
    expect(invalidEnum.value, LogicValue.ofString('xx'));

    final conditionalEnum = MyListLogicEnum()..inject(1);
    expect(
      conditionalEnum < Logic(width: conditionalEnum.width),
      isA<Conditional>(),
    );
  });

  test('enum type identity requires the same Dart type and exact mapping', () {
    final logicEnum = LogicEnum(TestEnum.values);
    final remapped = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 0,
      TestEnum.b: 2,
      TestEnum.c: 3,
    });
    final wider = LogicEnum(TestEnum.values, width: 3);

    expect(
      logicEnum.isEquivalentTypeTo(Logic(width: logicEnum.width)),
      isFalse,
    );
    expect(logicEnum.isEquivalentTypeTo(LogicEnum(OtherEnum.values)), isFalse);
    expect(logicEnum.isEquivalentTypeTo(remapped), isFalse);
    expect(() => logicEnum.gets(wider), throwsA(isA<ArgumentError>()));
  });

  test('conditional assignment validates known values and enum types', () {
    final logicEnum = LogicEnum(TestEnum.values);
    final incompatibleType = LogicEnum(OtherEnum.values);

    expect(() => logicEnum < 3, throwsA(isA<ArgumentError>()));
    expect(() => logicEnum < Const(3, width: logicEnum.width),
        throwsA(isA<ArgumentError>()));
    expect(() => logicEnum < OtherEnum.a, throwsA(isA<ArgumentError>()));
    expect(() => logicEnum < incompatibleType, throwsA(isA<ArgumentError>()));
    expect(logicEnum < TestEnum.b, isA<Conditional>());
    expect(logicEnum < 2, isA<Conditional>());
    expect(logicEnum < Const(2, width: logicEnum.width), isA<Conditional>());
  });

  test('untyped Logic rejects enum conditional values', () {
    expect(
      () => Logic(width: 2) < TestEnum.a,
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('LogicEnum receiver with an explicit mapping'),
        ),
      ),
    );
  });

  test('direct conditional enum assignments validate constants', () {
    final logicEnum = LogicEnum(TestEnum.values);
    expect(() => ConditionalAssign(logicEnum, Const(3, width: logicEnum.width)),
        throwsA(isA<ArgumentError>()));
    expect(ConditionalAssign(logicEnum, Const(2, width: logicEnum.width)),
        isA<Conditional>());
    expect(
      () => logicEnum < Const(2, width: logicEnum.width + 1),
      throwsA(isA<PortWidthMismatchException>()),
    );
  });

  test('enum conditional constants preserve metadata and other drivers', () {
    final receiver = LogicEnum(TestEnum.values);
    final constant = Const(2, width: 2, preferredRadix: 2);
    final assignment = ConditionalAssign(receiver, constant);
    expect(assignment.driver, same(constant));
    expect(assignment.driver.value, constant.value);
    expect(
        (assignment.driver as Const).preferredRadix, constant.preferredRadix);
    expect(
        () => assignment.driver.put(0), throwsA(isA<UnassignableException>()));
    expect(ConditionalAssign(Logic(width: 2), constant).driver, same(constant));

    final liveDriver = Logic(width: 2)..put(3);
    expect(ConditionalAssign(receiver, liveDriver).driver, same(liveDriver));
    expect(liveDriver.value.toInt(), 3);
  });

  test('sequential enum resets validate constants and require a legal default',
      () {
    for (final asyncReset in [false, true]) {
      for (final resetValue in [TestEnum.b, 1, Const(1, width: 2)]) {
        final receiver =
            LogicEnum<TestEnum>.withMapping({TestEnum.b: 1}, width: 2);
        expect(
          Sequential(Logic(), [receiver < TestEnum.b],
              reset: Logic(),
              asyncReset: asyncReset,
              resetValues: {receiver: resetValue}),
          isA<Sequential>(),
        );
      }

      for (final resetValue in [null, 0, Const(0, width: 2)]) {
        final receiver =
            LogicEnum<TestEnum>.withMapping({TestEnum.b: 1}, width: 2);
        expect(
          () => Sequential(Logic(), [receiver < TestEnum.b],
              reset: Logic(),
              asyncReset: asyncReset,
              resetValues: resetValue == null ? null : {receiver: resetValue}),
          throwsA(isA<ArgumentError>()),
        );
      }
    }
  });

  test('cases rejects enum keys outside the expression mapping', () {
    final expression = LogicEnum(TestEnum.values);
    final sparseExpression = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 0,
      TestEnum.c: 1,
    });

    expect(
      () => cases(expression, {OtherEnum.a: 0}, width: 1),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cases(sparseExpression, {TestEnum.b: 0}, width: 1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('cases rejects bare enum result values', () {
    final expression = LogicEnum(TestEnum.values);

    expect(
      () => cases(expression, {
        TestEnum.a: TestEnum.b,
        TestEnum.b: TestEnum.c,
      }),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('LogicEnum signal with an explicit mapping'),
        ),
      ),
    );
    expect(
      () => cases(expression, {
        TestEnum.a: TestEnum.b,
        TestEnum.b: Logic(width: expression.width),
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => cases(
        expression,
        {TestEnum.a: Logic(width: expression.width)},
        defaultValue: TestEnum.b,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('enum only allows legal values', () {
    final e = MyListLogicEnum();
    expect(e.value.isFloating, isTrue);
    e.put(0);
    expect(e.value.toInt(), 0);
    expect(e.valueEnum, TestEnum.a);
    e.put(1);
    expect(e.value.toInt(), 1);
    expect(e.valueEnum, TestEnum.b);
    e.put(2);
    expect(e.value.toInt(), 2);
    expect(e.valueEnum, TestEnum.c);
    e.put(3);
    expect(e.value, LogicValue.filled(e.width, LogicValue.x));
    expect(() => e.valueEnum, throwsStateError);
  });

  test('raw logic drivers are constrained in simulation', () async {
    final source = Logic(width: 2);
    final logicEnum = MyListLogicEnum()..gets(source);

    source.put(3);
    await Simulator.run();

    expect(logicEnum.value, LogicValue.filled(logicEnum.width, LogicValue.x));
  });

  test('enum constraints normalize a pre-driven shared wire', () {
    final source = Logic(width: 2)..put(3);
    final sibling = Logic(width: 2)..gets(source);
    final isThree = source.eq(3);
    final sourceChanges = <LogicValueChanged>[];
    source.glitch.listen(sourceChanges.add);
    final logicEnum = MyListLogicEnum()..gets(source);

    expect([source.value, sibling.value, logicEnum.value],
        everyElement(LogicValue.filled(2, LogicValue.x)));
    expect(isThree.value, LogicValue.x);
    expect(sourceChanges.single.previousValue, LogicValue.ofInt(3, 2));
    expect(sourceChanges.single.newValue, LogicValue.filled(2, LogicValue.x));

    source.put(2);
    expect([source.value, sibling.value, logicEnum.value],
        everyElement(LogicValue.ofInt(2, 2)));
    expect(logicEnum.valueEnum, TestEnum.c);

    sibling.put(3);
    expect([source.value, sibling.value, logicEnum.value],
        everyElement(LogicValue.filled(2, LogicValue.x)));
  });

  test('enum constraints normalize a downstream wire reconnection', () {
    final intermediate = Logic(width: 2);
    final sibling = Logic(width: 2)..gets(intermediate);
    final logicEnum = MyListLogicEnum()..gets(intermediate);
    final isThree = sibling.eq(3);
    final source = Logic(width: 2)..put(3);

    intermediate.gets(source);

    expect([source.value, intermediate.value, sibling.value, logicEnum.value],
        everyElement(LogicValue.filled(2, LogicValue.x)));
    expect(isThree.value, LogicValue.x);

    source.put(1);
    expect([source.value, intermediate.value, sibling.value, logicEnum.value],
        everyElement(LogicValue.ofInt(1, 2)));
    expect(logicEnum.valueEnum, TestEnum.b);
  });

  test('enum wire adoption preserves legal immutable sources', () {
    final source = Const(2, width: 2);
    final alias = Logic(width: 2)..gets(source);
    final logicEnum = MyListLogicEnum()..gets(alias);

    expect([source.value, alias.value, logicEnum.value],
        everyElement(LogicValue.ofInt(2, 2)));
    expect(logicEnum.valueEnum, TestEnum.c);
    expect(() => alias.put(3), throwsA(isA<UnassignableException>()));
  });

  test('enum puts with enums', () {
    final e = MyListLogicEnum()..put(TestEnum.b);
    expect(e.value.toInt(), TestEnum.b.index);
    expect(e.valueEnum, TestEnum.b);
  });

  test('enum injects with enums', () async {
    final logicEnum = MyListLogicEnum()..inject(TestEnum.c);

    await Simulator.run();

    expect(logicEnum.valueEnum, TestEnum.c);
  });

  test('synthesis merge policy preserves compatible enum metadata', () async {
    final module = EmptyModule();
    await module.build();
    final definition = SynthModuleDefinition(module);

    SynthLogic synth(Logic logic) => SynthLogic(
          logic,
          parentSynthModuleDefinition: definition,
        );

    final equivalentA = synth(LogicEnum(
      TestEnum.values,
      name: 'equivalentA',
      naming: Naming.mergeable,
    ));
    final equivalentB = synth(LogicEnum(
      TestEnum.values,
      name: 'equivalentB',
      naming: Naming.renameable,
    ));
    final equivalentResult = SynthLogic.tryMerge(equivalentA, equivalentB);
    expect(equivalentResult, isNotNull);
    expect(equivalentA.resolved, same(equivalentB.resolved));
    expect(equivalentResult!.kept.isEnum, isTrue);

    final incompatibleA = synth(LogicEnum(TestEnum.values));
    final incompatibleB = synth(LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 0,
      TestEnum.b: 2,
      TestEnum.c: 3,
    }));
    expect(SynthLogic.tryMerge(incompatibleA, incompatibleB), isNull);

    final enumLogic = synth(LogicEnum(TestEnum.values));
    final rawLogic = synth(Logic(width: 2));
    final rawResult = SynthLogic.tryMerge(enumLogic, rawLogic);
    expect(rawResult, isNotNull);
    expect(rawResult!.kept.isEnum, isTrue);

    final legalEnum = synth(LogicEnum(TestEnum.values));
    final legalConstant = synth(Const(2, width: 2));
    expect(SynthLogic.tryMerge(legalEnum, legalConstant), isNull);
    final typedConstant =
        legalConstant.constantWithEnumType(legalEnum.characteristicEnum!);
    expect(SynthLogic.tryMerge(legalEnum, typedConstant), isNotNull);
    expect(legalConstant.isEnum, isFalse);

    final illegalEnum = synth(LogicEnum(TestEnum.values));
    final illegalConstant = synth(Const(3, width: 2));
    expect(SynthLogic.tryMerge(illegalEnum, illegalConstant), isNull);

    final sharedConstant = synth(Const(1, width: 2));
    final typedFirst =
        sharedConstant.constantWithEnumType(LogicEnum(TestEnum.values));
    final typedSecond =
        sharedConstant.constantWithEnumType(LogicEnum(OtherEnum.values));
    expect(SynthLogic.tryMerge(sharedConstant, typedFirst), isNull);
    expect(SynthLogic.tryMerge(typedFirst, typedSecond), isNull);
    expect(sharedConstant.isEnum, isFalse);
    expect(sharedConstant.replacement, isNull);

    final reservedFirst = sharedConstant.constantWithEnumType(LogicEnum(
        TestEnum.values,
        definitionName: 'FirstEnum',
        reserveDefinitionName: true));
    final reservedSecond = sharedConstant.constantWithEnumType(LogicEnum(
        TestEnum.values,
        definitionName: 'SecondEnum',
        reserveDefinitionName: true));
    expect(SynthLogic.tryMerge(reservedFirst, reservedSecond), isNull);
  });

  group('enum sv gen', () {
    test('simple mod with enum gen good sv', () async {
      final mod = SimpleModWithEnum(Logic(width: 3));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      expect(
          sv,
          contains(
              "typedef enum logic [2:0] { a = 3'h1, c = 3'h7 } TestEnum;"));
      expect(sv, contains('TestEnum elephant;'));
    });

    test('conflicting enum mod gen good sv', () async {
      final mod = ConflictingEnumMod(Logic(width: 3));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      // Allocation order may choose either enum for the unsuffixed names.
      expect(
          sv,
          anyOf(
            contains('typedef enum logic [2:0]'
                " { a = 3'h1, c = 3'h7 } TestEnum;"),
            contains('typedef enum logic [2:0]'
                " { a_0 = 3'h1, c_0 = 3'h7 } TestEnum_0;"),
          ));
      expect(
          sv,
          anyOf(
            contains('typedef enum logic [1:0]'
                " { a = 2'h0, b = 2'h1, c = 2'h2 } TestEnum;"),
            contains('typedef enum logic [1:0]'
                " { a_0 = 2'h0, b = 2'h1, c_0 = 2'h2 } TestEnum_0;"),
          ));
    });

    test('enum constant assignment uses enum name', () async {
      final mod = ModWithEnumConstAssignment(Logic(width: 2));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      expect(
          sv,
          contains('typedef enum logic [1:0]'
              " { a = 2'h0, b = 2'h1, c = 2'h2 } TestEnum;"));
      expect(sv, contains('assign banana = carrot & b;'));
    });

    for (final directAssignments in [false, true]) {
      for (final sequential in [false, true]) {
        for (final generateEnums in [false, true]) {
          test(
              'shared enum constant direct=$directAssignments'
              ' sequential=$sequential enums=$generateEnums', () async {
            final module = SharedEnumConstantModule(Logic(),
                directAssignments: directAssignments,
                clock: sequential ? Logic() : null);
            await module.build();
            final vectors = [
              if (sequential) Vector({'clock': 0, 'select': 0}, {}),
              Vector({'select': 0, if (sequential) 'clock': 1},
                  {'first': 1, 'second': 1, 'raw': 1}),
              if (sequential)
                Vector({'clock': 0, 'select': 1},
                    {'first': 1, 'second': 1, 'raw': 1}),
              Vector({'select': 1, if (sequential) 'clock': 1},
                  {'first': 0, 'second': 0, 'raw': 0}),
            ];
            await SimCompare.checkFunctionalVector(module, vectors);
            SimCompare.checkIverilogVector(module, vectors,
                synthesizerConfiguration: SystemVerilogSynthesizerConfiguration(
                    generateEnums: generateEnums));
          });
        }
      }
    }

    for (final pairedModule in [false, true]) {
      for (final generateEnums in [false, true]) {
        test('shared constant fanout paired=$pairedModule enums=$generateEnums',
            () async {
          final module = SharedConstantFanoutModule(pairedModule: pairedModule);
          await module.build();
          final definition = SynthModuleDefinition(module);
          expect(definition.getSynthLogic(module.source)!.isEnum, isFalse);
          final vectors = [
            Vector({}, {'first': 1, 'second': 1, 'raw': 1})
          ];
          await SimCompare.checkFunctionalVector(module, vectors);
          SimCompare.checkIverilogVector(module, vectors,
              synthesizerConfiguration: SystemVerilogSynthesizerConfiguration(
                  generateEnums: generateEnums));
        });
      }
    }

    for (final generateEnums in [false, true]) {
      test('shared live input type uses enums=$generateEnums', () async {
        final module = SharedLiveFanoutModule(Logic(width: 2));
        await module.build();
        final configuration =
            SystemVerilogSynthesizerConfiguration(generateEnums: generateEnums);
        String synthesize() => SynthBuilder(
                module, SystemVerilogSynthesizer(configuration: configuration))
            .getSynthFileContents()
            .join();
        expect(synthesize(), synthesize());
        final vectors = [
          for (final value in [0, 1, 2])
            Vector({'source': value},
                {'first': value, 'second': value, 'raw': value}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors,
            synthesizerConfiguration: configuration);
      });
    }

    for (final generateEnums in [false, true]) {
      test('shared constant across module instances enums=$generateEnums',
          () async {
        final module = SharedConstantInstancesModule();
        await module.build();
        final vectors = [
          Vector({}, {'first': 1, 'second': 1, 'raw': 1})
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors,
            synthesizerConfiguration: SystemVerilogSynthesizerConfiguration(
                generateEnums: generateEnums));
      });
    }

    test('shared source contexts preserve netlist ports and stability',
        () async {
      for (final module in [
        SharedConstantFanoutModule(pairedModule: false),
        SharedConstantFanoutModule(pairedModule: true),
        SharedConstantInstancesModule(),
        SharedLiveFanoutModule(Logic(width: 2)),
      ]) {
        await module.build();
        final synthesizer = NetlistSynthesizer(
            configuration: NetlistSynthesizerConfiguration(
                moduleStopPolicy: SynthModuleStopPolicy()));
        final first = synthesizer.synthesizeToJson(module);
        expect(synthesizer.synthesizeToJson(module), first);
        final json = jsonDecode(first) as Map<String, dynamic>;
        final modules = json['modules'] as Map<String, dynamic>;
        expect(modules, isNotEmpty);
        for (final definition in modules.values.cast<Map<String, dynamic>>()) {
          final ports = definition['ports'] as Map<String, dynamic>;
          expect(ports.keys, containsAll(['first', 'second', 'raw']));
          for (final name in ['first', 'second', 'raw']) {
            expect(
                (ports[name] as Map<String, dynamic>)['direction'], 'output');
          }
        }
      }
    });

    test('shared enum constant compiles with Verilator', () async {
      final module = SharedEnumConstantModule(Logic(),
          directAssignments: true, clock: Logic());
      await module.build();
      SimCompare.checkVerilatorVector(module, const [], buildOnly: true);
    });

    test('generated enum SystemVerilog compiles and matches simulation',
        () async {
      final module = ModWithEnumConstAssignment(Logic(width: 2));
      await module.build();

      final vectors = [
        Vector({'carrot': 0}, {'banana': 0}),
        Vector({'carrot': 1}, {'banana': 1}),
        Vector({'carrot': 2}, {'banana': 0}),
        Vector({'carrot': 3}, {'banana': 1}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);
    });

    test('enum identifiers are uniquified and stable', () async {
      final module = EnumNameCollisionModule();
      await module.build();

      final firstSv = module.dumpSystemVerilog();
      final secondSv = module.dumpSystemVerilog();

      const typeDefinition =
          "typedef enum logic [1:0] { a_0 = 2'h0, b = 2'h1, c = 2'h2 } "
          'TestEnum_0;';
      expect(firstSv, contains(typeDefinition));
      expect(secondSv, contains(typeDefinition));
    });

    test('enum generation can be disabled', () async {
      final simpleModule = SimpleModWithEnum(Logic(width: 3));
      final constantModule = ModWithEnumConstAssignment(Logic(width: 2));
      final casesModule = EnumCasesModule(Logic(width: 2));
      await simpleModule.build();
      await constantModule.build();
      await casesModule.build();

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final simpleSv =
          simpleModule.dumpSystemVerilog(configuration: configuration);
      final constantSv =
          constantModule.dumpSystemVerilog(configuration: configuration);
      final casesSv =
          casesModule.dumpSystemVerilog(configuration: configuration);

      expect(simpleSv, isNot(contains('typedef enum')));
      expect(simpleSv, contains('logic [2:0] elephant;'));
      expect(constantSv, isNot(contains('typedef enum')));
      expect(constantSv, contains("assign banana = carrot & 2'h1;"));
      expect(casesSv, isNot(contains('typedef enum')));
      expect(casesSv, isNot(contains("TestEnum'(")));
      SimCompare.checkIverilogVector(
        casesModule,
        [
          Vector({'selector': 0}, {'result': 1}),
          Vector({'selector': 1}, {'result': 2}),
          Vector({'selector': 2}, {'result': 0}),
        ],
        synthesizerConfiguration: configuration,
      );
    });

    test('cases supports explicitly mapped enum result signals', () async {
      final module = EnumCasesModule(Logic(width: 2));
      await module.build();

      expect(module.selected, isNot(isA<LogicEnum<TestEnum>>()));
      expect(module.result, isA<LogicEnum<TestEnum>>());
      expect(module.dumpSystemVerilog(), contains("TestEnum'(selector)"));
      final vectors = [
        Vector({'selector': 0}, {'result': 1}),
        Vector({'selector': 1}, {'result': 2}),
        Vector({'selector': 2}, {'result': 0}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);
    });

    test('subset enum assignment casts between distinct enum types', () async {
      final module = EnumSubsetAssignmentModule(Logic(width: 2));
      await module.build();

      final sv = module.dumpSystemVerilog();
      expect(
        sv,
        contains(
          "typedef enum logic [1:0] { a = 2'h0, b = 2'h1, c = 2'h2 } "
          'BroadEnum;',
        ),
      );
      expect(
        sv,
        contains(
          "typedef enum logic [1:0] { a_0 = 2'h0, b_0 = 2'h1 } NarrowEnum;",
        ),
      );
      expect(sv, contains("assign broad = BroadEnum'(narrow);"));

      final vectors = [
        Vector({'selector': 0}, {'result': 0}),
        Vector({'selector': 1}, {'result': 1}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, isNot(contains('typedef enum')));
      expect(untypedSv, contains('assign broad = narrow;'));
      SimCompare.checkIverilogVector(
        module,
        vectors,
        synthesizerConfiguration: configuration,
      );
    });

    test('conditional subset enum assignment synthesizes', () async {
      final module = EnumSubsetConditionalAssignmentModule(Logic(width: 2));
      await module.build();

      final sv = module.dumpSystemVerilog();
      expect(sv, contains("BroadEnum'(narrow)"));

      final vectors = [
        Vector({'selector': 0}, {'result': 0}),
        Vector({'selector': 1}, {'result': 1}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, isNot(contains('typedef enum')));
      expect(untypedSv, isNot(contains("BroadEnum'(")));
      SimCompare.checkIverilogVector(
        module,
        vectors,
        synthesizerConfiguration: configuration,
      );
    });

    test('enum driven from a packed slice synthesizes in both modes', () async {
      final module = EnumFromSliceModule(Logic(width: 8));
      await module.build();

      final vectors = [
        Vector({'source': 0x00}, {'result': 0}),
        Vector({'source': 0x04}, {'result': 1}),
        Vector({'source': 0x08}, {'result': 2}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains("TestEnum'("));
      SimCompare.checkIverilogVector(module, vectors);

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, isNot(contains('typedef enum')));
      expect(untypedSv, isNot(contains("TestEnum'(")));
      SimCompare.checkIverilogVector(
        module,
        vectors,
        synthesizerConfiguration: configuration,
      );
    });

    test('enum assembled from assigned bits synthesizes in both modes',
        () async {
      final module = EnumFromAssignedBitsModule(Logic(width: 2));
      final vectors = [
        Vector({'source': 0}, {'result': 0}),
        Vector({'source': 1}, {'result': 1}),
        Vector({'source': 2}, {'result': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      expect(
        module.dumpSystemVerilog(),
        contains("assign state = TestEnum'(source);"),
      );
    });

    test('partially assigned enum generates compilable SystemVerilog',
        () async {
      final module = PartiallyAssignedEnumModule(Logic());
      await module.build();

      SimCompare.checkIverilogVector(module, [], buildOnly: true);
      SimCompare.checkIverilogVector(
        module,
        [],
        buildOnly: true,
        synthesizerConfiguration:
            const SystemVerilogSynthesizerConfiguration(generateEnums: false),
      );
    });

    test('single-value enum synthesizes in both modes', () async {
      final module = SingleValueEnumModule();
      await checkEnumModeParity(
        module,
        [
          Vector({}, {'result': 0})
        ],
      );

      expect(module.dumpSystemVerilog(), contains('enum logic [0:0]'));
    });

    test('wide sparse enum synthesizes in both modes', () async {
      final module = WideSparseEnumModule();
      final vectors = [
        Vector({}, {'result': WideSparseEnumModule.wideValue}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('enum logic [80:0]'));
      expect(sv, contains("c = 81'h100000000000000000000"));
    });

    test('enum leaf in a structure preserves behavior in both modes', () async {
      final module = EnumStructureModule(Logic(width: 4));
      final vectors = [
        Vector(
          {'source': 0x0},
          {'stateResult': 0, 'packedResult': 0x0, 'rangeResult': 0},
        ),
        Vector(
          {'source': 0x5},
          {'stateResult': 1, 'packedResult': 0x5, 'rangeResult': 1},
        ),
        Vector(
          {'source': 0xa},
          {'stateResult': 2, 'packedResult': 0xa, 'rangeResult': 2},
        ),
      ];
      await checkEnumModeParity(module, vectors);

      expect(module.dumpSystemVerilog(), contains("TestEnum'("));
    });

    test('raw unpacked array lane feeds enum in both modes', () async {
      final module = EnumArrayBoundaryModule(Logic(width: 4));
      final vectors = [
        Vector({'source': 0x0}, {'stateResult': 0, 'packedResult': 0x0}),
        Vector({'source': 0x4}, {'stateResult': 1, 'packedResult': 0x4}),
        Vector({'source': 0xa}, {'stateResult': 2, 'packedResult': 0xa}),
      ];
      await checkEnumModeParity(module, vectors);

      expect(module.dumpSystemVerilog(), contains("TestEnum'("));
    });

    test('enum metadata crosses a submodule boundary in both modes', () async {
      final module = EnumHierarchyModule(Logic(width: 2));
      final vectors = [
        Vector({'source': 0}, {'result': 0}),
        Vector({'source': 1}, {'result': 1}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('ChildNarrowEnum'));
      expect(sv, contains('ParentBroadEnum'));
    });

    test('typed enum input and output preserve type in both modes', () async {
      final source = LogicEnum<TestEnum>.withMapping(
        {
          TestEnum.a: 0,
          TestEnum.c: 2,
        },
        width: 2,
        definitionName: 'TypedPortEnum',
      );
      final module = TypedEnumPortsModule(source);

      expect(module.stateIn, isA<LogicEnum<TestEnum>>());
      expect(module.stateOut, isA<LogicEnum<TestEnum>>());
      expect(module.stateIn.mapping, source.mapping);
      expect(module.stateOut.mapping, source.mapping);

      final vectors = [
        Vector({'stateIn': 0}, {'stateOut': 0}),
        Vector({'stateIn': 2}, {'stateOut': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('input logic [1:0] stateIn'));
      expect(sv, contains('output logic [1:0] stateOut'));
      expect(sv, contains('} TypedPortEnum;'));
      expect(sv, contains('TypedPortEnum stateIn_enum;'));
      expect(sv, contains('TypedPortEnum stateOut_enum;'));
      expect(
        sv,
        contains("assign stateIn_enum = TypedPortEnum'(stateIn);"),
      );
      expect(sv, contains('assign stateOut = stateOut_enum;'));
      expect(sv, contains('assign stateOut_enum = stateIn_enum;'));

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, isNot(contains('stateIn_enum')));
      expect(untypedSv, isNot(contains('stateOut_enum')));
    });

    test('typed enum input survives partial assignment rewriting', () async {
      final type = LogicEnum<TestEnum>.withMapping(
        {
          TestEnum.a: 0,
          TestEnum.b: 1,
        },
        width: 1,
        definitionName: 'TypedPartialEnum',
      );
      final module = TypedEnumPartialSourceModule(type);
      final vectors = [
        Vector({'stateIn': 0}, {'result': 0}),
        Vector({'stateIn': 1}, {'result': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('assign packedValue[1] = stateIn_enum;'));
      expect(
        sv,
        contains("assign stateIn_enum = TypedPartialEnum'(stateIn);"),
      );

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, contains('assign packedValue[1] = stateIn;'));
      expect(untypedSv, isNot(contains('stateIn_enum')));
    });

    test('typed enum output survives range assignment rewriting', () async {
      final type = LogicEnum(
        TestEnum.values,
        width: 2,
        definitionName: 'TypedRangeEnum',
      );
      final module = TypedEnumRangeDestinationModule(Logic(width: 2), type);
      final vectors = [
        Vector({'source': 0}, {'stateOut': 0}),
        Vector({'source': 1}, {'stateOut': 1}),
        Vector({'source': 2}, {'stateOut': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(
        sv,
        contains("assign stateOut_enum = TypedRangeEnum'(source);"),
      );
      expect(sv, contains('assign stateOut = stateOut_enum;'));

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, contains('assign stateOut = source;'));
      expect(untypedSv, isNot(contains('stateOut_enum')));
    });

    test('typed enum ports preserve widening across hierarchy in both modes',
        () async {
      final module = TypedEnumHierarchyModule(Logic(width: 2));
      final vectors = [
        Vector({'source': 0}, {'result': 0}),
        Vector({'source': 2}, {'result': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      expect(module.child.stateIn.mapping.keys, [TestEnum.a, TestEnum.c]);
      expect(module.child.stateOut.mapping, module.child.stateIn.mapping);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('TypedChildNarrowEnum'));
      expect(sv, contains('ParentTypedBroadEnum'));
      expect(sv, contains("ParentTypedBroadEnum'("));
    });

    test('typed enum backing signals are used by cases in both modes',
        () async {
      final source = LogicEnum<TestEnum>.withMapping(
        {
          TestEnum.a: 0,
          TestEnum.c: 2,
        },
        width: 2,
        definitionName: 'TypedCaseEnum',
      );
      final module = TypedEnumCasesModule(source);
      final vectors = [
        Vector({'stateIn': 0}, {'stateOut': 2}),
        Vector({'stateIn': 2}, {'stateOut': 0}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('case (stateIn_enum)'));
      expect(sv, contains('stateOut_enum = c;'));
      expect(sv, contains('stateOut_enum = a;'));

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, isNot(contains('stateIn_enum')));
      expect(untypedSv, isNot(contains('stateOut_enum')));
    });

    test('typed enum backing names avoid signal collisions', () async {
      final source = LogicEnum<TestEnum>.withMapping(
        {
          TestEnum.a: 0,
          TestEnum.c: 2,
        },
        width: 2,
        definitionName: 'TypedCollisionEnum',
      );
      final module = TypedEnumPortNameCollisionModule(source);
      final vectors = [
        Vector({'stateIn': 0}, {'result': 0}),
        Vector({'stateIn': 2}, {'result': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final firstSv = module.dumpSystemVerilog();
      final secondSv = module.dumpSystemVerilog();
      for (final sv in [firstSv, secondSv]) {
        expect(sv, contains('logic [1:0] stateIn_enum;'));
        expect(sv, contains('TypedCollisionEnum stateIn_enum_0;'));
        expect(
          sv,
          contains("assign stateIn_enum_0 = TypedCollisionEnum'(stateIn);"),
        );
      }
    });

    test('typed enum backing signals feed inline and child consumers',
        () async {
      final source = LogicEnum<TestEnum>.withMapping(
        {
          TestEnum.a: 0,
          TestEnum.c: 2,
        },
        width: 2,
        definitionName: 'TypedConsumerEnum',
      );
      final module = TypedEnumConsumersModule(source);
      final vectors = [
        Vector({'stateIn': 0}, {'inlineResult': 1, 'childResult': 0}),
        Vector({'stateIn': 2}, {'inlineResult': 3, 'childResult': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains("stateIn_enum ^ 2'h1"));
      expect(sv, contains('.stateIn(stateIn_enum)'));

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.dumpSystemVerilog(configuration: configuration);
      expect(untypedSv, isNot(contains('stateIn_enum')));
    });

    test('typed enum inOut requires a net-backed enum type', () {
      final module = EmptyModule();
      final logicEnum = LogicEnum(TestEnum.values);

      expect(
        () => module.addTypedInOut('state', logicEnum),
        throwsA(
          isA<PortTypeException>().having(
            (error) => error.message,
            'message',
            contains('must be nets'),
          ),
        ),
      );
    });

    test('if-else mixes widened enum and enum constant in both modes',
        () async {
      final module = EnumIfElseModule(Logic(width: 2), Logic());
      final vectors = [
        Vector({'source': 0, 'select': 1}, {'result': 0}),
        Vector({'source': 1, 'select': 1}, {'result': 1}),
        Vector({'source': 0, 'select': 0}, {'result': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('if(select)'));
      expect(sv, contains('else begin'));
    });

    test('enum with case and cond assignments', () async {
      final mod = ModWithCaseAndEnumCondAssign(Logic());
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      expect(sv, contains(' a : begin'));
      expect(sv, contains('nextState = a;'));
    });
  });
}

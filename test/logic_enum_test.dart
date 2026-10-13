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

class MappingCountingLogicEnum extends LogicEnum<TestEnum> {
  int mappingReads = 0;

  MappingCountingLogicEnum(super.mapping, {super.name, super.naming})
      : super.withMapping(width: 2);

  @override
  Map<TestEnum, LogicValue> get mapping {
    mappingReads++;
    return super.mapping;
  }

  @override
  MappingCountingLogicEnum clone({String? name}) => MappingCountingLogicEnum(
        mapping,
        name: name ?? this.name,
        naming: Naming.chooseCloneNaming(
          originalName: this.name,
          newName: name,
          originalNaming: naming,
          newNaming: null,
        ),
      );
}

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
  ModWithEnumConstAssignment(Logic carrot, {bool includeUnusedEnum = false}) {
    carrot = addInput('carrot', carrot, width: 2);
    final e = MyListLogicEnum(name: 'elephant')..getsEnum(TestEnum.b);
    addOutput('banana', width: 2) <= carrot & e;
    if (includeUnusedEnum) {
      final unused = LogicEnum(OtherEnum.values, definitionName: 'UnusedEnum')
        ..getsEnum(OtherEnum.a);
      carrot | unused;
    }
  }
}

class RawConstantEnumAssignmentModule extends Module {
  RawConstantEnumAssignmentModule(LogicValue value,
      {Naming? naming, Logic? clock}) {
    final alias = Const(value).named('namedLiteral', naming: naming);
    final state = MyListLogicEnum(name: 'enumState', naming: Naming.reserved);
    final conditionals = [state < alias];
    if (clock == null) {
      Combinational(conditionals);
    } else {
      Sequential(addInput('clock', clock), conditionals);
    }
    addOutput('result', width: state.width) <= state;
    addOutput('raw', width: alias.width) <= alias;
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

class PairedEnumConstantModule extends Module {
  PairedEnumConstantModule(Logic source) {
    final firstInput = addTypedInput<Logic>('firstInput', source);
    final secondInput = addTypedInput<Logic>('secondInput', source);
    final rawInput = addTypedInput<Logic>('rawInput', source);
    final first = addTypedOutput('first', LogicEnum(TestEnum.values).clone);
    final second = addTypedOutput('second', LogicEnum(OtherEnum.values).clone);
    final raw = addOutput('raw', width: 2);
    first <= firstInput;
    second <= secondInput;
    raw <= rawInput;
  }
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

class PairedTypedEnumInputModule extends Module with SystemVerilog {
  PairedTypedEnumInputModule(Logic source,
      {List<int> encodings = const [0, 1, 2], bool sameEnumType = false}) {
    final first = addTypedInput(
        'firstInput',
        LogicEnum<TestEnum>.withMapping(
            Map.fromIterables(TestEnum.values, encodings),
            width: source.width)
          ..gets(source));
    final secondType = sameEnumType
        ? LogicEnum<TestEnum>.withMapping(
            Map.fromIterables(TestEnum.values, encodings.reversed),
            width: source.width)
        : LogicEnum<OtherEnum>.withMapping(
            Map.fromIterables(OtherEnum.values, encodings.reversed),
            width: source.width);
    final second = addTypedInput('secondInput', secondType..gets(source));
    addOutput('first', width: source.width) <= first;
    addOutput('second', width: source.width) <= second;
  }

  @override
  String? definitionVerilog(String definitionType) => null;
}

class SharedConstantInstancesModule extends Module {
  SharedConstantInstancesModule({
    bool typedInputs = false,
    Logic? driver,
    Naming? aliasNaming = Naming.mergeable,
    List<int> enumEncodings = const [0, 1, 2],
    bool sameEnumType = false,
  }) {
    var source = driver ?? Const(1, width: 2);
    if (source is! Const) {
      source = addInput('source', source, width: source.width);
    }
    final alias = aliasNaming == null
        ? source
        : (Logic(name: 'sharedAlias', width: source.width, naming: aliasNaming)
          ..gets(source));
    Module createChild(Logic source) => typedInputs
        ? PairedTypedEnumInputModule(source,
            encodings: enumEncodings, sameEnumType: sameEnumType)
        : PairedEnumConstantModule(source);
    final first = createChild(source);
    final second = createChild(alias);
    addOutput('first', width: source.width) <= first.output('first');
    addOutput('second', width: source.width) <= second.output('second');
    addOutput('raw', width: source.width) <= alias;
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
  EnumNameCollisionModule({Logic? source}) {
    final enumSignal = MyListLogicEnum(name: 'a');
    if (source != null) {
      enumSignal.gets(addInput('source', source, width: 2));
    }
    addOutput('TestEnum', width: enumSignal.width) <= enumSignal;
    addOutput('a');
  }
}

class ReservedEnumNameCollisionModule extends Module {
  ReservedEnumNameCollisionModule(Logic source,
      {String secondDefinitionName = 'SharedType'}) {
    source = addInput('source', source, width: 2);
    final first = LogicEnum(
      TestEnum.values,
      name: 'a',
      naming: Naming.renameable,
      definitionName: 'SharedType',
      reserveDefinitionName: true,
    )..gets(source);
    final second = LogicEnum(
      OtherEnum.values,
      name: 'SharedType',
      naming: Naming.renameable,
      definitionName: secondDefinitionName,
      reserveDefinitionName: true,
    )..gets(source);
    addOutput('first', width: 2) <= first;
    addOutput('second', width: 2) <= second;
  }
}

class MixedReservedEnumModule extends Module {
  MixedReservedEnumModule(
      {required bool reservedFirst,
      String flexibleDefinitionName = 'FlexibleType'}) {
    final flexible =
        LogicEnum(OtherEnum.values, definitionName: flexibleDefinitionName);
    final reserved = LogicEnum(TestEnum.values,
        definitionName: 'RequiredType', reserveDefinitionName: true);
    for (final isReserved in [reservedFirst, !reservedFirst]) {
      final name = isReserved ? 'strict' : 'flexible';
      final port = addTypedInput(name, isReserved ? reserved : flexible);
      addOutput('${name}Result', width: port.width) <= port;
    }
  }
}

class MixedReservedEnumExternalModule extends MixedReservedEnumModule
    with SystemVerilog {
  MixedReservedEnumExternalModule({required super.reservedFirst});
}

class EnumNameStabilityModule extends Module {
  EnumNameStabilityModule(Logic source,
      {required bool reserved, Naming signalNaming = Naming.renameable}) {
    source = addInput('source', source, width: 2);
    final state = LogicEnum(
      TestEnum.values,
      name: 'SharedType',
      naming: signalNaming,
      definitionName: 'SharedType',
      reserveDefinitionName: reserved,
    )..gets(source);
    final member = state.clone(name: 'a')..gets(source);
    addOutput('first', width: 2) <= state;
    addOutput('second', width: 2) <= member;
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

class EnumCasePatternModule extends Module {
  EnumCasePatternModule(Logic selector, Logic pattern,
      {bool wildcard = true, bool? wildcardFirst, Logic? clock}) {
    selector = addInput('selector', selector, width: 2);
    final enumSelector = LogicEnum(TestEnum.values)..gets(selector);
    final matched = addOutput('matched');
    addOutput('pattern', width: 2) <= pattern;
    final caseConstructor = wildcard ? CaseZ.new : Case.new;
    final conditionals = <Conditional>[
      caseConstructor(enumSelector, [
        CaseItem(pattern, [matched < 1]),
      ], defaultItem: [
        matched < 0
      ]),
    ];
    if (wildcardFirst != null) {
      final strictMatched = addOutput('strictMatched');
      final strictCase = Case(enumSelector, [
        CaseItem(pattern, [strictMatched < 1]),
      ], defaultItem: [
        strictMatched < 0
      ]);
      conditionals.insert(wildcardFirst ? 1 : 0, strictCase);
    }
    if (clock == null) {
      Combinational(conditionals);
    } else {
      Sequential(addInput('clock', clock), conditionals);
    }
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
  EnumSubsetConditionalAssignmentModule(Logic selector, {bool direct = false}) {
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

    Combinational([
      if (direct) ConditionalAssign(broad, narrow) else broad < narrow,
    ]);
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

class MergedEnumPortAssignmentModule extends Module {
  MergedEnumPortAssignmentModule(Logic source, {Logic? clock}) {
    source = addInput('source', source, width: 3);
    final alias = MyMapLogicEnum(
      name: 'aliasedState',
      naming: Naming.mergeable,
    )..gets(source);
    final stored = MyMapLogicEnum(
      name: 'storedState',
      naming: Naming.renameable,
    );
    final merged = MyMapLogicEnum(
      name: 'mergedState',
      naming: Naming.mergeable,
    );
    final conditionals = [stored < alias, merged < alias];
    if (clock == null) {
      Combinational(conditionals);
    } else {
      Sequential(addInput('clock', clock), conditionals);
    }
    addOutput('result', width: 3) <= stored;
    addOutput('mergedResult', width: 3) <= merged;
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

class PackedEnumBoundaryChild extends Module with SystemVerilog {
  Logic get result => output('result');

  PackedEnumBoundaryChild(Logic source) {
    source = addInput('source', source, width: source.width);
    addOutput('result', width: source.width) <= source;
  }

  @override
  String? definitionVerilog(String definitionType) => null;
}

class TypedEnumSplitOutputModule extends Module {
  TypedEnumSplitOutputModule(Logic source) {
    source = addInput('source', source, width: 4);
    final child = PackedEnumBoundaryChild(source);
    addTypedOutput('stateOut', MyListLogicEnum().clone) <=
        child.result.getRange(0, 2);
    addOutput('other', width: 2) <= child.result.getRange(2, 4);
  }
}

class TypedEnumSliceInputModule extends Module {
  TypedEnumSliceInputModule(LogicEnum<TestEnum> source) {
    final stateIn = addTypedInput('stateIn', source);
    final packedValue = Logic(width: 3)
      ..assignSubset([stateIn[3], ...stateIn.getRange(1, 3).elements]);
    final child = PackedEnumBoundaryChild(packedValue);
    addOutput('result', width: 3) <= child.result;
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

class EnumComparisonModule extends Module {
  EnumComparisonModule(LogicEnum<TestEnum> state) {
    state = addTypedInput('state', state);
    addOutput('equal') <= state.eq(TestEnum.c);
    addOutput('notEqual') <= state.neq(TestEnum.c);
    addOutput('less') <= state.lt(TestEnum.c);
    addOutput('lessOrEqual') <= state.lte(TestEnum.c);
    addOutput('greater') <= state.gt(TestEnum.c);
    addOutput('greaterOrEqual') <= state.gte(TestEnum.c);
    addOutput('greaterOperator') <= (state > TestEnum.c);
    addOutput('greaterOrEqualOperator') <= (state >= TestEnum.c);
    addOutput('member') <= state.isIn([TestEnum.a, TestEnum.c]);
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

  test('enum list constructor rejects duplicate members', () {
    for (final values in [
      [TestEnum.a, TestEnum.a],
      [TestEnum.c, TestEnum.b, TestEnum.c],
    ]) {
      for (final width in [null, 4]) {
        expect(() => LogicEnum(values, width: width),
            throwsA(isA<ArgumentError>()));
      }
    }
  });

  test('enum list constructor preserves unique member order', () {
    for (final width in [null, 4]) {
      final values = [TestEnum.c, TestEnum.a, TestEnum.b];
      final logicEnum = LogicEnum(values, width: width);

      expect(logicEnum.width, width ?? 2);
      expect(logicEnum.mapping.keys, orderedEquals(values));
      expect(logicEnum.mapping, {
        TestEnum.c: LogicValue.ofInt(0, logicEnum.width),
        TestEnum.a: LogicValue.ofInt(1, logicEnum.width),
        TestEnum.b: LogicValue.ofInt(2, logicEnum.width),
      });
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
    expect(() => LogicEnum<TestEnum>([]), throwsA(isA<ArgumentError>()));
  });

  test('enum comparisons encode literals using the receiver mapping', () {
    final state = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 6,
      TestEnum.b: 1,
      TestEnum.c: 3,
    }, width: 4, name: 'state', definitionName: 'StateType');
    final Logic signal = state;
    final comparisons = [
      signal.eq(TestEnum.c),
      signal.neq(TestEnum.c),
      signal.lt(TestEnum.c),
      signal.lte(TestEnum.c),
      signal.gt(TestEnum.c),
      signal.gte(TestEnum.c),
      signal > TestEnum.c,
      signal >= TestEnum.c,
      signal.isIn([TestEnum.a, TestEnum.c]),
    ];

    expect(comparisons.first.name, contains('state_equals_StateType_c'));
    expect(comparisons.take(8).map((comparison) => comparison.name),
        everyElement(contains('StateType_c')));
    expect(signal.eq(3).name, contains('const_3'));

    for (final (member, expected) in [
      (TestEnum.a, [0, 1, 0, 0, 1, 1, 1, 1, 1]),
      (TestEnum.b, [0, 1, 1, 1, 0, 0, 0, 0, 0]),
      (TestEnum.c, [1, 0, 0, 1, 0, 1, 0, 1, 1]),
    ]) {
      state.put(member);
      expect(
          comparisons.map((comparison) => comparison.value.toInt()), expected);
    }

    for (final value in ['xxxx', 'zzzz', '00x1', 2]) {
      state.put(value);
      expect(comparisons.map((comparison) => comparison.value),
          everyElement(LogicValue.x));
    }
  });

  test('enum comparisons reject wrong enum types and unmapped members', () {
    final state = MyMapLogicEnum();
    final comparisons = <Logic Function(dynamic)>[
      state.eq,
      state.neq,
      state.lt,
      state.lte,
      state.gt,
      state.gte,
      (other) => state > other,
      (other) => state >= other,
      (other) => state.isIn([TestEnum.a, other]),
    ];

    for (final compare in comparisons) {
      expect(() => compare(OtherEnum.a), throwsA(isA<ArgumentError>()));
      expect(() => compare(TestEnum.b), throwsA(isA<ArgumentError>()));
    }
  });

  test('enum comparisons preserve raw operands and symmetric comparisons', () {
    final state = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 0,
      TestEnum.c: 3,
    }, width: 2)
      ..put(TestEnum.c);
    final raw = Logic(width: 2)..gets(state);
    final broad = LogicEnum(TestEnum.values)..put(TestEnum.b);
    final conflicting = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 3,
      TestEnum.c: 0,
    }, width: 2)
      ..put(TestEnum.a);
    final otherType = LogicEnum(OtherEnum.values)..put(OtherEnum.a);

    for (final operand in [
      0,
      1,
      3,
      BigInt.from(3),
      true,
      '11',
      LogicValue.ofInt(3, 2),
      Const(3, width: 2),
      raw,
      broad,
      conflicting,
      otherType,
    ]) {
      expect(state.eq(operand).value, raw.eq(operand).value);
      expect(state.neq(operand).value, raw.neq(operand).value);
      expect(state.gt(operand).value, raw.gt(operand).value);
    }

    expect(state.eq(broad).value, broad.eq(state).value);
    expect(state.eq(conflicting).value, LogicValue.one);
    expect(state.isIn([TestEnum.a, 1, raw]).value, LogicValue.one);
    expect(state.isIn([]).value, LogicValue.zero);
    expect(state.value, LogicValue.ofInt(3, 2));
    expect(broad.value, LogicValue.ofInt(1, 2));
    expect(state == state, isTrue);
    expect(state == state.clone(), isFalse);
    expect(() => state.eq(Logic()), throwsA(isA<PortWidthMismatchException>()));
  });

  test('enum comparisons support wide mapped literals', () {
    final encoding = (BigInt.one << 80) | BigInt.from(3);
    final state = LogicEnum<TestEnum>.withMapping({
      TestEnum.a: encoding,
      TestEnum.b: 5,
    }, width: 96)
      ..put(TestEnum.a);
    final equal = state.eq(TestEnum.a);
    final notEqual = state.neq(TestEnum.a);
    final greater = state.gt(TestEnum.b);

    expect(equal.value, LogicValue.one);
    expect(notEqual.value, LogicValue.zero);
    expect(greater.value, LogicValue.one);
    state.put(TestEnum.b);
    expect(equal.value, LogicValue.zero);
    expect(notEqual.value, LogicValue.one);
    expect(greater.value, LogicValue.zero);
  });

  test('enum comparisons synthesize mapped literals in both modes', () async {
    final module = EnumComparisonModule(LogicEnum<TestEnum>.withMapping({
      TestEnum.a: 6,
      TestEnum.b: 1,
      TestEnum.c: 3,
    }, width: 4));

    await checkEnumModeParity(module, [
      Vector({
        'state': 6
      }, {
        'equal': 0,
        'notEqual': 1,
        'less': 0,
        'lessOrEqual': 0,
        'greater': 1,
        'greaterOrEqual': 1,
        'greaterOperator': 1,
        'greaterOrEqualOperator': 1,
        'member': 1,
      }),
      Vector({
        'state': 1
      }, {
        'equal': 0,
        'notEqual': 1,
        'less': 1,
        'lessOrEqual': 1,
        'greater': 0,
        'greaterOrEqual': 0,
        'greaterOperator': 0,
        'greaterOrEqualOperator': 0,
        'member': 0,
      }),
      Vector({
        'state': 3
      }, {
        'equal': 1,
        'notEqual': 0,
        'less': 0,
        'lessOrEqual': 1,
        'greater': 0,
        'greaterOrEqual': 1,
        'greaterOperator': 0,
        'greaterOrEqualOperator': 1,
        'member': 1,
      }),
    ]);
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

  for (final direct in [false, true]) {
    test('conditional enum assignment validates typed drivers direct=$direct',
        () {
      Conditional assign(LogicEnum<TestEnum> receiver, Logic driver) =>
          direct ? ConditionalAssign(receiver, driver) : receiver < driver;
      final receiver = LogicEnum(TestEnum.values);
      final narrow = LogicEnum<TestEnum>.withMapping({
        TestEnum.a: 0,
        TestEnum.b: 1,
      }, width: 2);
      final conflicting = LogicEnum<TestEnum>.withMapping({
        TestEnum.a: 1,
        TestEnum.b: 0,
        TestEnum.c: 2,
      });

      expect(() => assign(receiver, LogicEnum(OtherEnum.values)),
          throwsA(isA<ArgumentError>()));
      expect(
          () => assign(receiver, conflicting), throwsA(isA<ArgumentError>()));
      expect(() => assign(narrow, receiver), throwsA(isA<ArgumentError>()));
      expect(assign(receiver, receiver.clone()), isA<ConditionalAssign>());
      expect(
          (assign(receiver, narrow) as ConditionalAssign).driver, same(narrow));
      expect(assign(receiver, Logic(width: 2)), isA<ConditionalAssign>());
    });
  }

  for (final direct in [false, true]) {
    for (final sequential in [false, true]) {
      test(
          'subset conditional preserves normalization'
          ' direct=$direct sequential=$sequential', () async {
        final source = Logic(width: 2)..put(0);
        final sibling = Logic(width: 2)..gets(source);
        final narrow = LogicEnum<TestEnum>.withMapping({
          TestEnum.a: 0,
          TestEnum.b: 1,
        }, width: 2)
          ..gets(source);
        final broad = LogicEnum(TestEnum.values);
        final assignment =
            direct ? ConditionalAssign(broad, narrow) : broad < narrow;
        final clock = Logic()..put(0);
        if (sequential) {
          Sequential(clock, [assignment]);
        } else {
          Combinational([assignment]);
        }

        final zero = LogicValue.ofInt(0, 2);
        final one = LogicValue.ofInt(1, 2);
        final unknown = LogicValue.filled(2, LogicValue.x);
        final floating = LogicValue.filled(2, LogicValue.z);
        final cases = <(Object, LogicValue)>[
          (1, one),
          (2, unknown),
          ('xx', unknown),
          ('0x', unknown),
          ('0z', unknown),
          ('zz', floating),
          (0, zero),
        ];
        Simulator.registerAction(1, () => clock.put(1));
        Simulator.registerAction(2, () => expect(broad.value, zero));
        var previousOutput = zero;
        for (var index = 0; index < cases.length; index++) {
          final (input, expectedSource) = cases[index];
          final expectedOutput =
              expectedSource.isFloating ? unknown : expectedSource;
          final heldValue = previousOutput;
          previousOutput = expectedOutput;
          final time = 10 + index * 10;
          Simulator.registerAction(time, () {
            clock.put(0);
            source.put(input);
          });
          Simulator.registerAction(time + 1, () {
            expect([
              source.value,
              sibling.value,
              narrow.value
            ], everyElement(expectedSource), reason: 'Source value $input');
            expect(broad.value, sequential ? heldValue : expectedOutput,
                reason: 'Before clock edge with $input');
          });
          Simulator.registerAction(time + 2, () {
            clock.put(1);
          });
          Simulator.registerAction(time + 3, () {
            expect(broad.value, expectedOutput, reason: 'Sampled value $input');
          });
          if (sequential) {
            Simulator.registerAction(time + 4, () => source.put(1));
            Simulator.registerAction(time + 5, () {
              expect(broad.value, expectedOutput,
                  reason: 'Held value after sampling $input');
            });
          }
        }
        if (sequential) {
          final time = 10 + cases.length * 10;
          Simulator.registerAction(time, () {
            clock.put(0);
            source.put(0);
          });
          Simulator.registerAction(time + 1, () {
            clock.put(1);
            source.put(1);
          });
          Simulator.registerAction(time + 2, () {
            expect(broad.value, unknown, reason: 'Clock/input race');
          });
        }
        await Simulator.run();
      });
    }
  }

  for (final direct in [false, true]) {
    test('subset conditional samples the previous flop value direct=$direct',
        () async {
      final source = Logic(width: 2)..put(0);
      final clock = Logic()..put(0);
      final narrow = LogicEnum<TestEnum>.withMapping({
        TestEnum.a: 0,
        TestEnum.b: 1,
      }, width: 2);
      final broad = LogicEnum(TestEnum.values);
      Sequential(clock, [narrow < source]);
      Sequential(clock, [
        if (direct) ConditionalAssign(broad, narrow) else broad < narrow,
      ]);
      narrow.put(0);
      broad.put(0);

      var previousValue = LogicValue.ofInt(0, 2);
      final inputs = [1, 0, 2, 1];
      for (var index = 0; index < inputs.length; index++) {
        final input = inputs[index];
        final sampledValue = previousValue;
        final nextValue = input == 2
            ? LogicValue.filled(2, LogicValue.x)
            : LogicValue.ofInt(input, 2);
        previousValue = nextValue;
        final time = 10 + index * 10;
        Simulator.registerAction(time, () {
          clock.put(0);
          source.put(input);
        });
        Simulator.registerAction(time + 2, () => clock.put(1));
        Simulator.registerAction(time + 3, () {
          expect(narrow.value, nextValue);
          expect(broad.value, sampledValue);
        });
      }
      await Simulator.run();
    });
  }

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

  test('enum contract uses receiver mappings across write APIs', () async {
    final scheduledResults = <LogicEnum<TestEnum>, LogicValue>{};
    for (final mapping in [
      {TestEnum.a: 4, TestEnum.b: 2, TestEnum.c: 7},
      {TestEnum.a: 3, TestEnum.b: 6, TestEnum.c: 0},
    ]) {
      final mutable = LogicEnum<TestEnum>.withMapping(mapping, width: 4);
      for (final entry in mapping.entries) {
        final expected = LogicValue.ofInt(entry.value, 4);
        mutable.put(entry.key);
        expect(mutable.value, expected);
        expect(mutable.valueEnum, entry.key);
        final injected = mutable.clone()..inject(entry.key);
        scheduledResults[injected] = expected;

        final tied = mutable.clone()..getsEnum(entry.key);
        expect(tied, isNot(isA<Const>()));
        expect(tied.value, expected);
        final packed = mutable.clone()..gets(Const(entry.value, width: 4));
        expect(packed.value, expected);

        final conditional = mutable.clone();
        Combinational([conditional < entry.key]);
        scheduledResults[conditional] = expected;
      }
    }
    await Simulator.run();
    for (final entry in scheduledResults.entries) {
      expect(entry.key.value, entry.value);
    }
  });

  test('enum contract clone stays driveable when its source is constant-driven',
      () {
    for (final reserveName in [false, true]) {
      final original = LogicEnum<TestEnum>.withMapping(
        {TestEnum.a: 4, TestEnum.b: 2, TestEnum.c: 7},
        width: 4,
        name: 'original',
        definitionName: 'MappedState',
        reserveDefinitionName: reserveName,
      )..getsEnum(TestEnum.a);
      final clone = original.clone(name: 'copy');

      expect(clone, isA<LogicEnum<TestEnum>>());
      expect(clone, isNot(isA<Const>()));
      expect(clone, isNot(same(original)));
      expect(clone.mapping, original.mapping);
      expect(clone.width, original.width);
      expect(clone.definitionName, original.definitionName);
      expect(clone.reserveDefinitionName, reserveName);
      expect(clone.value.isFloating, isTrue);

      clone.put(TestEnum.b);
      expect(clone.valueEnum, TestEnum.b);
      final source = Logic(width: clone.width)..put(7);
      clone.gets(source);
      expect(clone.valueEnum, TestEnum.c);
      source.put(2);
      expect(clone.valueEnum, TestEnum.b);
      expect(original.valueEnum, TestEnum.a);
    }
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

  test('enum constraints are not duplicated by upstream reconnections', () {
    final logicEnum = MappingCountingLogicEnum({
      TestEnum.a: 0,
      TestEnum.b: 1,
      TestEnum.c: 2,
    });
    Logic source = logicEnum;

    for (var depth = 1; depth <= 8; depth++) {
      final upstream = Logic(width: 2);
      source.gets(upstream);
      source = upstream;

      logicEnum.mappingReads = 0;
      source.put(1);

      expect(logicEnum.mappingReads, 1, reason: 'Reconnection depth $depth');
      expect(logicEnum.value, LogicValue.ofInt(1, 2));
    }
  });

  test('enum constraints remain distinct when shared wires merge', () {
    final firstSource = Logic(width: 2);
    final secondSource = Logic(width: 2);
    final first = MappingCountingLogicEnum({TestEnum.a: 0, TestEnum.b: 1})
      ..gets(firstSource);
    final second = MappingCountingLogicEnum({TestEnum.b: 1, TestEnum.c: 2})
      ..gets(secondSource);
    final sibling = Logic(width: 2)..gets(firstSource);
    final source = Logic(width: 2);

    firstSource.gets(secondSource);
    secondSource.gets(source);

    final signals = [source, firstSource, secondSource, first, second, sibling];
    first.mappingReads = 0;
    second.mappingReads = 0;
    source.put(1);

    expect(first.mappingReads, 1);
    expect(second.mappingReads, 1);
    expect(signals.map((signal) => signal.value),
        everyElement(LogicValue.ofInt(1, 2)));

    for (final value in [0, 2, '0z']) {
      sibling.put(value);
      expect(signals.map((signal) => signal.value),
          everyElement(LogicValue.filled(2, LogicValue.x)));
    }

    source.put(LogicValue.z, fill: true);
    expect(signals.map((signal) => signal.value),
        everyElement(LogicValue.filled(2, LogicValue.z)));
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

  test('immutable enum adoption rejects normalization before mutation', () {
    for (final throughUpstream in [false, true]) {
      for (final invalidValue in [
        LogicValue.ofInt(3, 2),
        LogicValue.ofString('0z'),
      ]) {
        final logicEnum = MyListLogicEnum();
        final receiver = throughUpstream ? Logic(width: 2) : logicEnum;
        if (throughUpstream) {
          logicEnum.gets(receiver);
        }
        receiver.put(1);
        final sibling = Logic(width: 2)..gets(receiver);
        final source = Const(invalidValue);
        final alias = source.named('immutableAlias');
        final receiverChanges = <LogicValueChanged>[];
        final sourceChanges = <LogicValueChanged>[];
        receiver.glitch.listen(receiverChanges.add);
        alias.glitch.listen(sourceChanges.add);

        expect(
            () => receiver.gets(alias), throwsA(isA<UnassignableException>()));
        expect(receiver.srcConnection, isNull);
        expect(receiver.srcConnections, isEmpty);
        expect(alias.dstConnections, isEmpty);
        expect([receiver.value, logicEnum.value, sibling.value],
            everyElement(LogicValue.ofInt(1, 2)));
        expect([source.value, alias.value], everyElement(invalidValue));
        expect(receiverChanges, isEmpty);
        expect(sourceChanges, isEmpty);

        receiver.put(2);
        expect(logicEnum.valueEnum, TestEnum.c);
        receiver.gets(Const(1, width: 2).named('validAlias'));
        expect([receiver.value, logicEnum.value, sibling.value],
            everyElement(LogicValue.ofInt(1, 2)));
        expect([source.value, alias.value], everyElement(invalidValue));
        expect(sourceChanges, isEmpty);
      }
    }
  });

  test('immutable enum adoption accepts unchanged mapped X and Z aliases', () {
    for (final value in [
      LogicValue.ofInt(2, 2),
      LogicValue.filled(2, LogicValue.x),
      LogicValue.filled(2, LogicValue.z),
    ]) {
      final alias = Const(value).named('immutableAlias');
      final logicEnum = MyListLogicEnum()..gets(alias);
      expect(logicEnum.srcConnection, same(alias));
      expect([alias.value, logicEnum.value], everyElement(value));
      expect(() => alias.put(1), throwsA(isA<UnassignableException>()));
    }
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

  test('connection reference replacement preserves nested views', () async {
    final module = EmptyModule();
    await module.build();
    final definition = SynthModuleDefinition(module);
    SynthLogic synth(int width) => SynthLogic(Logic(width: width),
        parentSynthModuleDefinition: definition);
    final source = synth(4);
    final alias = synth(4)..replacement = source;
    final backing = synth(4);
    final untouched = synth(1);
    final range = SynthLogicPackedRangeReference(alias, 1, 2,
        parentSynthModuleDefinition: definition);
    final bit = SynthLogicPackedBitReference(source, 3,
        parentSynthModuleDefinition: definition);
    final nested = SynthLogicConcat([bit, untouched],
        parentSynthModuleDefinition: definition);
    final view = SynthLogicConcat([range, nested],
        parentSynthModuleDefinition: definition);

    expect(view.replaceReferences({}), same(view));
    final rewritten =
        view.replaceReferences({source: backing}) as SynthLogicConcat;
    final rewrittenRange = rewritten.parts[0] as SynthLogicPackedRangeReference;
    final rewrittenNested = rewritten.parts[1] as SynthLogicConcat;
    final rewrittenBit =
        rewrittenNested.parts[0] as SynthLogicPackedBitReference;

    expect(rewritten.width, view.width);
    expect(rewrittenRange.packedBase, same(backing));
    expect(rewrittenRange.lowerIndex, 1);
    expect(rewrittenRange.upperIndex, 2);
    expect(rewrittenBit.packedBase, same(backing));
    expect(rewrittenBit.bitIndex, 3);
    expect(rewrittenNested.parts[1], same(untouched));
    expect(view.parts, [range, nested]);
    expect(range.packedBase, same(alias));
    expect(bit.packedBase, same(source));
    expect(alias.resolved, same(source));
    expect(source.replacement, isNull);
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

    for (final (naming, sequential) in [
      (Naming.mergeable, false),
      (Naming.unnamed, true),
      (null, false),
    ]) {
      test('raw constant enum assignment naming=$naming sequential=$sequential',
          () async {
        for (final value in [
          LogicValue.ofInt(3, 2),
          LogicValue.ofInt(1, 2),
          LogicValue.ofString('0z'),
        ]) {
          await Simulator.reset();
          final module = RawConstantEnumAssignmentModule(value,
              naming: naming, clock: sequential ? Logic() : null);
          await module.build();
          final expectedResult = value == LogicValue.ofInt(1, 2)
              ? value
              : LogicValue.filled(2, LogicValue.x);
          final vectors = [
            if (sequential) Vector({'clock': 0}, {'raw': value}),
            Vector({if (sequential) 'clock': 1},
                {'result': expectedResult, 'raw': value}),
          ];
          await SimCompare.checkFunctionalVector(module, vectors);

          final json = jsonDecode(NetlistSynthesizer(
                  configuration: NetlistSynthesizerConfiguration(
                      moduleStopPolicy: SynthModuleStopPolicy()))
              .synthesizeToJson(module)) as Map<String, dynamic>;
          final definition =
              (json['modules'] as Map)[module.definitionName] as Map;
          final netnames = definition['netnames'] as Map;
          final rawAttributes = (netnames['raw'] as Map)['attributes'] as Map;
          final enumAttributes =
              (netnames['enumState'] as Map)['attributes'] as Map;
          expect(rawAttributes, isNot(contains('wiretype')));
          expect(enumAttributes, containsPair('wiretype', r'\TestEnum'));
          expect(enumAttributes, isNot(contains('enum_value_11')));

          for (final generateEnums in [false, true]) {
            final configuration = SystemVerilogSynthesizerConfiguration(
                generateEnums: generateEnums);
            String synthesize() => SynthBuilder(module,
                    SystemVerilogSynthesizer(configuration: configuration))
                .getSynthFileContents()
                .join();
            final sv = synthesize();
            expect(synthesize(), sv);
            expect(sv.contains('logic [1:0] namedLiteral;'), naming == null);
            if (expectedResult.isValid) {
              SimCompare.checkIverilogVector(module, vectors,
                  synthesizerConfiguration: configuration);
            } else {
              expect(sv, contains(value.toString()));
              expect(sv.contains("TestEnum'("), generateEnums);
            }
            SimCompare.checkVerilatorVector(module, const [],
                buildOnly: true, synthesizerConfiguration: configuration);
          }
        }
      });
    }

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

    for (final (constant, aliasNaming, sparse) in [
      for (final constant in [false, true])
        for (final aliasNaming in [null, Naming.mergeable, Naming.reserved])
          (constant, aliasNaming, false),
      for (final constant in [false, true]) (constant, Naming.reserved, true),
    ]) {
      test(
          'shared typed inputs constant=$constant'
          ' alias=${aliasNaming?.name ?? 'direct'} sparse=$sparse', () async {
        final encodings = sparse ? [1, 3, 6] : [0, 1, 2];
        final width = sparse ? 3 : 2;
        final constantValue = sparse ? encodings.first : encodings[1];
        final driver =
            constant ? Const(constantValue, width: width) : Logic(width: width);
        final module = SharedConstantInstancesModule(
          typedInputs: true,
          driver: driver,
          aliasNaming: aliasNaming,
          enumEncodings: encodings,
          sameEnumType: sparse,
        );
        await module.build();
        final definition = SynthModuleDefinition(module);
        final endpoints = [
          for (final assignment in definition.assignments)
            if (assignment is! PartialSynthAssignment)
              (assignment.src.resolved, assignment.dst.resolved),
        ];
        expect(endpoints.toSet(), hasLength(endpoints.length));
        final vectors = [
          for (final value in constant ? [constantValue] : encodings)
            Vector(constant ? {} : {'source': value},
                {'first': value, 'second': value, 'raw': value}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        for (final generateEnums in [false, true]) {
          final configuration = SystemVerilogSynthesizerConfiguration(
              generateEnums: generateEnums);
          String synthesize() => SynthBuilder(module,
                  SystemVerilogSynthesizer(configuration: configuration))
              .getSynthFileContents()
              .join();
          expect(synthesize(), synthesize());
          SimCompare.checkIverilogVector(module, vectors,
              synthesizerConfiguration: configuration);
          if (constant && aliasNaming == Naming.mergeable) {
            SimCompare.checkVerilatorVector(module, const [],
                buildOnly: true, synthesizerConfiguration: configuration);
          }
        }

        final netlist = jsonDecode(NetlistSynthesizer(
                configuration: NetlistSynthesizerConfiguration(
                    moduleStopPolicy: SynthModuleStopPolicy()))
            .synthesizeToJson(module)) as Map<String, dynamic>;
        final modules = netlist['modules'] as Map<String, dynamic>;
        final child =
            module.subModules.whereType<PairedTypedEnumInputModule>().first;
        final childDefinition = modules[child.definitionName] as Map;
        final netnames = childDefinition['netnames'] as Map;
        final firstAttributes =
            (netnames['firstInput'] as Map)['attributes'] as Map;
        final secondAttributes =
            (netnames['secondInput'] as Map)['attributes'] as Map;
        expect(firstAttributes['wiretype'], r'\TestEnum');
        expect(secondAttributes['wiretype'],
            sparse ? startsWith(r'\TestEnum') : r'\OtherEnum');
        expect(
            secondAttributes['wiretype'], isNot(firstAttributes['wiretype']));
        for (final encoding in encodings) {
          final key =
              'enum_value_${encoding.toRadixString(2).padLeft(width, '0')}';
          expect(firstAttributes, contains(key));
          expect(secondAttributes, contains(key));
          expect(firstAttributes[key], isNot(secondAttributes[key]));
        }
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
          final netnames = definition['netnames'] as Map<String, dynamic>;
          final netAttributes = netnames.map((name, netname) => MapEntry(
              name, (netname as Map)['attributes'] as Map<String, dynamic>));
          for (final name in ['first', 'second']) {
            final attributes = netAttributes[name]!;
            expect(attributes, contains('wiretype'));
            expect(
                attributes.keys,
                containsAll(
                    ['enum_value_00', 'enum_value_01', 'enum_value_10']));
          }
          expect(netAttributes['raw'], isNot(contains('wiretype')));
          expect(netAttributes['first']!['wiretype'], r'\TestEnum');
          expect(netAttributes['second']!['wiretype'], r'\OtherEnum');
          expect(netAttributes['first']!['enum_value_01'],
              isNot(netAttributes['second']!['enum_value_01']));
        }
      }
    });

    test(
        'enum netlist retains constant literal metadata after packed synthesis',
        () async {
      final module =
          ModWithEnumConstAssignment(Logic(width: 2), includeUnusedEnum: true);
      await module.build();
      expect(
        module.dumpSystemVerilog(
            configuration: const SystemVerilogSynthesizerConfiguration(
                generateEnums: false)),
        isNot(contains('typedef enum')),
      );
      final json = jsonDecode(NetlistSynthesizer().synthesizeToJson(module))
          as Map<String, dynamic>;
      final definition = (json['modules'] as Map).values.single as Map;
      final netnames = definition['netnames'] as Map;
      final enumNets = netnames.values.cast<Map<String, dynamic>>().where(
          (netname) => (netname['attributes'] as Map).containsKey('wiretype'));
      expect(enumNets, hasLength(1));
      expect(enumNets.single['attributes'],
          containsPair('wiretype', r'\TestEnum'));
      expect(
          enumNets.single['attributes'], containsPair('enum_value_00', r'\a'));
      expect(
          enumNets.single['attributes'], containsPair('enum_value_01', r'\b'));
      expect(
          enumNets.single['attributes'], containsPair('enum_value_10', r'\c'));
      final constantBits = (definition['cells'] as Map)
          .values
          .cast<Map<String, dynamic>>()
          .where((cell) => cell['type'] == r'$const')
          .expand((cell) => (cell['connections'] as Map).values)
          .expand((bits) => bits as List)
          .toSet();
      expect(enumNets.single['bits'], everyElement(isIn(constantBits)));
      expect(json.keys, unorderedEquals(['creator', 'version', 'modules']));
      expect(module.dumpSystemVerilog(), contains('typedef enum'));
    });

    test('enum netlist preserves sparse and wide encodings', () async {
      for (final (module, typeName, members) in [
        (SingleValueEnumModule(), r'\SingleState', {'0': r'\only'}),
        (
          WideSparseEnumModule(),
          r'\WideSparseState',
          {
            '0' * 81: r'\a',
            '1${'0' * 80}': r'\c',
          }
        ),
      ]) {
        await module.build();
        final json = jsonDecode(NetlistSynthesizer(
                configuration: NetlistSynthesizerConfiguration(
                    moduleStopPolicy: SynthModuleStopPolicy()))
            .synthesizeToJson(module)) as Map<String, dynamic>;
        final definition = (json['modules'] as Map).values.single as Map;
        final netnames = definition['netnames'] as Map;
        final enumAttributes = netnames.values
            .cast<Map<String, dynamic>>()
            .map((netname) => netname['attributes'] as Map)
            .where((attributes) => attributes.containsKey('wiretype'));
        expect(enumAttributes, isNotEmpty);
        for (final attributes in enumAttributes) {
          expect(attributes['wiretype'], typeName);
          expect(
              Map.fromEntries(attributes.entries.where(
                  (entry) => (entry.key as String).startsWith('enum_value_'))),
              {
                for (final entry in members.entries)
                  'enum_value_${entry.key}': entry.value
              });
        }
      }
    });

    test('enum netlist names use the shared synthesis namespace', () async {
      final module = EnumNameCollisionModule(source: Logic(width: 2));
      await module.build();
      final json = jsonDecode(NetlistSynthesizer(
              configuration: NetlistSynthesizerConfiguration(
                  enableDeadCellElimination: false,
                  moduleStopPolicy: SynthModuleStopPolicy()))
          .synthesizeToJson(module)) as Map<String, dynamic>;
      final definition = (json['modules'] as Map).values.single as Map;
      final enumAttributes = (definition['netnames'] as Map)
          .values
          .cast<Map<String, dynamic>>()
          .map((netname) => netname['attributes'] as Map)
          .where((attributes) => attributes.containsKey('wiretype'));
      expect(enumAttributes, isNotEmpty);
      for (final attributes in enumAttributes) {
        expect(attributes, containsPair('wiretype', r'\TestEnum_0'));
        expect(attributes, containsPair('enum_value_00', r'\a_0'));
      }
    });

    for (final slimMode in [false, true]) {
      for (final eliminateDeadCells in [false, true]) {
        test('enum netlist service slim=$slimMode prune=$eliminateDeadCells',
            () async {
          for (final module in [
            ModWithEnumConstAssignment(Logic(width: 2)),
            TypedEnumPortsModule(LogicEnum<TestEnum>.withMapping(
                {TestEnum.a: 4, TestEnum.c: 7},
                width: 4)),
          ]) {
            await module.build();
            final service = NetlistService(module,
                register: false,
                configuration: NetlistSynthesizerConfiguration(
                    slimMode: slimMode,
                    enableDeadCellElimination: eliminateDeadCells,
                    moduleStopPolicy: SynthModuleStopPolicy()));
            final typeName = module.definitionName;
            final full = jsonDecode(service.moduleJson(typeName))
                as Map<String, dynamic>;
            final fullModules = full['modules'] as Map;
            final netnames = (fullModules[typeName] as Map)['netnames'] as Map;
            expect(
                netnames.values.cast<Map<String, dynamic>>().where((netname) =>
                    (netname['attributes'] as Map).containsKey('wiretype')),
                isNotEmpty);
            if (module is TypedEnumPortsModule) {
              final inputAttributes =
                  (netnames['stateIn'] as Map)['attributes'];
              final outputAttributes =
                  (netnames['stateOut'] as Map)['attributes'];
              expect(inputAttributes, outputAttributes);
              expect(inputAttributes, containsPair('enum_value_0100', r'\a'));
              expect(inputAttributes, containsPair('enum_value_0111', r'\c'));
            }
            for (final view in [
              jsonDecode(service.json) as Map,
              (jsonDecode(service.slimJson) as Map)['netlist'] as Map,
            ]) {
              expect(view['version'], full['version']);
              final modules = view['modules'] as Map;
              expect((modules[typeName] as Map)['netnames'], netnames);
            }
          }
        });
      }
    }

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

    for (final (typedFirst, secondDefinitionName) in [
      (false, 'SharedType'),
      (true, 'SharedType'),
      (false, 'OtherType'),
    ]) {
      test(
          'packed enums defer collisions $secondDefinitionName '
          'typedFirst=$typedFirst', () async {
        final module = ReservedEnumNameCollisionModule(Logic(width: 2),
            secondDefinitionName: secondDefinitionName);
        await module.build();
        final collision =
            throwsA(isA<UnavailableReservedNameException>().having(
          (error) => error.toString(),
          'conflicting identifier',
          contains(
              secondDefinitionName == 'SharedType' ? '"SharedType"' : '"a"'),
        ));
        if (typedFirst) {
          expect(module.dumpSystemVerilog, collision);
        }

        const configuration =
            SystemVerilogSynthesizerConfiguration(generateEnums: false);
        String synthesizePacked() => SynthBuilder(
                module, SystemVerilogSynthesizer(configuration: configuration))
            .getSynthFileContents()
            .join();
        final packedSv = synthesizePacked();
        expect(packedSv, isNot(contains('typedef enum')));
        expect(packedSv, isNot(contains("SharedType'(")));
        expect(packedSv, isNot(contains('logic [1:0] a;')));
        expect(packedSv, isNot(contains('logic [1:0] SharedType;')));
        expect(synthesizePacked(), packedSv);
        expect(module.dumpSystemVerilog, collision);
        expect(synthesizePacked(), packedSv);

        final vectors = [
          for (final value in [0, 1, 2])
            Vector({'source': value}, {'first': value, 'second': value}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors,
            synthesizerConfiguration: configuration);
        SimCompare.checkVerilatorVector(module, const [],
            buildOnly: true, synthesizerConfiguration: configuration);
      });
    }

    for (final reserved in [false, true]) {
      test('enum names stay stable across output modes reserved=$reserved',
          () async {
        for (final firstMode in ['packed', 'enum', 'netlist']) {
          await Simulator.reset();
          final module =
              EnumNameStabilityModule(Logic(width: 2), reserved: reserved);
          await module.build();
          final vectors = [
            for (final value in [0, 1, 2])
              Vector({'source': value}, {'first': value, 'second': value}),
          ];
          await SimCompare.checkFunctionalVector(module, vectors);

          String synthesize({required bool generateEnums}) => SynthBuilder(
                  module,
                  SystemVerilogSynthesizer(
                      configuration: SystemVerilogSynthesizerConfiguration(
                          generateEnums: generateEnums)))
              .getSynthFileContents()
              .join();
          final snapshots = <String, String>{};
          for (final mode in [firstMode, 'packed', 'enum', 'netlist']) {
            if (mode == 'netlist') {
              final json = jsonDecode(NetlistSynthesizer(
                      configuration: NetlistSynthesizerConfiguration(
                          moduleStopPolicy: SynthModuleStopPolicy()))
                  .synthesizeToJson(module)) as Map<String, dynamic>;
              final definition = (json['modules'] as Map).values.single as Map;
              final attributes = (definition['netnames'] as Map)
                  .values
                  .cast<Map<String, dynamic>>()
                  .map((netname) => netname['attributes'] as Map)
                  .where((attributes) => attributes.containsKey('wiretype'));
              expect(attributes, isNotEmpty);
              for (final attribute in attributes) {
                expect(attribute, containsPair('wiretype', r'\SharedType'));
                expect(attribute, containsPair('enum_value_00', r'\a'));
              }
            } else {
              final generateEnums = mode == 'enum';
              final sv = synthesize(generateEnums: generateEnums);
              expect(sv, snapshots.putIfAbsent(mode, () => sv));
              final type = generateEnums ? 'SharedType' : 'logic [1:0]';
              expect(sv, contains('$type SharedType_0;'));
              expect(sv, contains('$type a_0;'));
              expect(sv.contains('typedef enum'), generateEnums);
            }
          }
          for (final generateEnums in [false, true]) {
            expect(synthesize(generateEnums: generateEnums),
                snapshots[generateEnums ? 'enum' : 'packed']);
            final configuration = SystemVerilogSynthesizerConfiguration(
                generateEnums: generateEnums);
            SimCompare.checkIverilogVector(module, vectors,
                synthesizerConfiguration: configuration);
            SimCompare.checkVerilatorVector(module, const [],
                buildOnly: true, synthesizerConfiguration: configuration);
          }
        }
      });
    }

    for (final (reservedFirst, flexibleDefinitionName) in [
      (false, 'FlexibleType'),
      (true, 'FlexibleType'),
      (false, 'RequiredType'),
    ]) {
      test(
          'mixed reserved enum names take priority '
          'reservedFirst=$reservedFirst '
          'flexibleDefinitionName=$flexibleDefinitionName', () async {
        for (final firstMode in ['packed', 'enum', 'netlist']) {
          await Simulator.reset();
          final module = MixedReservedEnumModule(
              reservedFirst: reservedFirst,
              flexibleDefinitionName: flexibleDefinitionName);
          await module.build();
          final flexibleType = flexibleDefinitionName == 'RequiredType'
              ? 'RequiredType_0'
              : flexibleDefinitionName;
          final snapshots = <String, String>{};
          for (final mode in [
            firstMode,
            'packed',
            'enum',
            'netlist',
            'packed',
            'enum',
          ]) {
            if (mode == 'netlist') {
              final json = jsonDecode(NetlistSynthesizer(
                      configuration: NetlistSynthesizerConfiguration(
                          moduleStopPolicy: SynthModuleStopPolicy()))
                  .synthesizeToJson(module)) as Map<String, dynamic>;
              final definition = (json['modules'] as Map).values.single as Map;
              final netnames = definition['netnames'] as Map;
              final strict = (netnames['strict'] as Map)['attributes'] as Map;
              final flexible =
                  (netnames['flexible'] as Map)['attributes'] as Map;
              expect(strict, containsPair('wiretype', r'\RequiredType'));
              expect(strict, containsPair('enum_value_00', r'\a'));
              expect(flexible, containsPair('wiretype', '\\$flexibleType'));
              expect(flexible, containsPair('enum_value_00', r'\a_0'));
            } else {
              final generateEnums = mode == 'enum';
              final sv = SynthBuilder(
                      module,
                      SystemVerilogSynthesizer(
                          configuration: SystemVerilogSynthesizerConfiguration(
                              generateEnums: generateEnums)))
                  .getSynthFileContents()
                  .join();
              expect(sv, snapshots.putIfAbsent(mode, () => sv));
              expect(sv.contains('typedef enum'), generateEnums);
              if (generateEnums) {
                expect(
                    sv,
                    contains("{ a = 2'h0, b = 2'h1, c = 2'h2 } "
                        'RequiredType;'));
                expect(
                    sv,
                    contains("{ a_0 = 2'h0, b_0 = 2'h1, c_0 = 2'h2 } "
                        '$flexibleType;'));
              }
            }
          }
          final vectors = [
            for (final value in [0, 1, 2])
              Vector({'strict': value, 'flexible': 2 - value},
                  {'strictResult': value, 'flexibleResult': 2 - value}),
          ];
          await SimCompare.checkFunctionalVector(module, vectors);
          for (final generateEnums in [false, true]) {
            final configuration = SystemVerilogSynthesizerConfiguration(
                generateEnums: generateEnums);
            SimCompare.checkIverilogVector(module, vectors,
                synthesizerConfiguration: configuration);
            SimCompare.checkVerilatorVector(module, const [],
                buildOnly: true, synthesizerConfiguration: configuration);
          }
        }
      });
    }

    test('mixed reserved enum names take priority on external netlist ports',
        () async {
      for (final reservedFirst in [false, true]) {
        final module =
            MixedReservedEnumExternalModule(reservedFirst: reservedFirst);
        await module.build();
        expect(module.generatedDefinitionType, DefinitionGenerationType.none);
        final json = jsonDecode(NetlistSynthesizer(
                configuration: NetlistSynthesizerConfiguration(
                    moduleStopPolicy: SynthModuleStopPolicy()))
            .synthesizeToJson(module)) as Map<String, dynamic>;
        final definition = (json['modules'] as Map).values.single as Map;
        final netnames = definition['netnames'] as Map;
        final strict = (netnames['strict'] as Map)['attributes'] as Map;
        final flexible = (netnames['flexible'] as Map)['attributes'] as Map;
        expect(strict, containsPair('wiretype', r'\RequiredType'));
        expect(strict, containsPair('enum_value_00', r'\a'));
        expect(flexible, containsPair('wiretype', r'\FlexibleType'));
        expect(flexible, containsPair('enum_value_00', r'\a_0'));
      }
    });

    test('packed enum planning respects reserved signal names', () async {
      final module = EnumNameStabilityModule(Logic(width: 2),
          reserved: true, signalNaming: Naming.reserved);
      await module.build();
      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final sv = module.dumpSystemVerilog(configuration: configuration);
      expect(sv, contains('logic [1:0] SharedType;'));
      expect(module.dumpSystemVerilog,
          throwsA(isA<UnavailableReservedNameException>()));
      SimCompare.checkVerilatorVector(module, const [],
          buildOnly: true, synthesizerConfiguration: configuration);
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

    for (final generateEnums in [false, true]) {
      final configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: generateEnums);
      for (final entry in {
        '1z': [0, 0, 1],
        'z0': [1, 0, 1],
        'zz': [1, 1, 1],
        '10': [0, 0, 1],
      }.entries) {
        for (final alias in [false, true]) {
          test(
              'enum case pattern ${entry.key} alias=$alias'
              ' enums=$generateEnums', () async {
            final value = LogicValue.ofString(entry.key);
            final constant = Const(value);
            final pattern = alias
                ? (Logic(name: 'patternAlias', width: 2)..gets(constant))
                : constant;
            final module = EnumCasePatternModule(Logic(width: 2), pattern);
            await module.build();
            final vectors = [
              for (var selector = 0; selector < 3; selector++)
                Vector({'selector': selector},
                    {'matched': entry.value[selector], 'pattern': value}),
            ];
            await SimCompare.checkFunctionalVector(module, vectors);
            SimCompare.checkIverilogVector(module, vectors,
                synthesizerConfiguration: configuration);
            final firstSv =
                module.dumpSystemVerilog(configuration: configuration);
            if (entry.key.contains('z')) {
              expect(firstSv, contains("2'b${entry.key}"));
            } else if (generateEnums && !alias) {
              expect(firstSv, contains('c : begin'));
            }
            String synthesize() => SynthBuilder(module,
                    SystemVerilogSynthesizer(configuration: configuration))
                .getSynthFileContents()
                .join();
            expect(synthesize(), synthesize());
            expect(pattern.value, value);
          });
        }
      }

      for (final wildcard in [false, true]) {
        for (final pattern in ['11', '1x', if (!wildcard) '1z']) {
          test(
              'enum case rejects $pattern wildcard=$wildcard'
              ' enums=$generateEnums', () async {
            final module = EnumCasePatternModule(
                Logic(width: 2), Const(LogicValue.ofString(pattern)),
                wildcard: wildcard);
            await module.build();
            expect(
                () => module.dumpSystemVerilog(configuration: configuration),
                throwsA(isStateError.having((error) => error.message, 'message',
                    contains('Constant is not representable'))));
          });
        }
      }

      for (final wildcardFirst in [false, true]) {
        test(
            'enum case shared pattern remains strict'
            ' wildcardFirst=$wildcardFirst enums=$generateEnums', () async {
          final module = EnumCasePatternModule(
              Logic(width: 2), Const(LogicValue.ofString('1z')),
              wildcardFirst: wildcardFirst);
          await module.build();
          expect(
              () => module.dumpSystemVerilog(configuration: configuration),
              throwsA(isStateError.having((error) => error.message, 'message',
                  contains('Constant is not representable'))));
        });
      }

      test('enum case wildcard sequential enums=$generateEnums', () async {
        final value = LogicValue.ofString('1z');
        final pattern = Logic(width: 2)..gets(Const(value));
        final module =
            EnumCasePatternModule(Logic(width: 2), pattern, clock: Logic());
        await module.build();
        final vectors = [
          Vector({'clock': 0, 'selector': 0}, {'pattern': value}),
          Vector({'clock': 1}, {'matched': 0, 'pattern': value}),
          Vector({'clock': 0, 'selector': 2}, {'matched': 0}),
          Vector({'clock': 1}, {'matched': 1}),
          Vector({'clock': 0, 'selector': 1}, {'matched': 1}),
          Vector({'clock': 1}, {'matched': 0}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors,
            synthesizerConfiguration: configuration);
      });
    }

    test('enum case wildcard support does not permit wildcard assignments', () {
      final receiver = LogicEnum(TestEnum.values);
      final wildcard = Const(LogicValue.ofString('1z'));
      expect(() => receiver < wildcard, throwsArgumentError);
      expect(() => ConditionalAssign(receiver, wildcard), throwsArgumentError);
      expect(() => receiver.gets(wildcard), throwsArgumentError);
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

    for (final direct in [false, true]) {
      test('conditional subset enum assignment synthesizes direct=$direct',
          () async {
        final module = EnumSubsetConditionalAssignmentModule(Logic(width: 2),
            direct: direct);
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
        final untypedSv =
            module.dumpSystemVerilog(configuration: configuration);
        expect(untypedSv, isNot(contains('typedef enum')));
        expect(untypedSv, isNot(contains("BroadEnum'(")));
        SimCompare.checkIverilogVector(
          module,
          vectors,
          synthesizerConfiguration: configuration,
        );
      });
    }

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

    for (final sequential in [false, true]) {
      test(
          'raw ports merged with enum aliases in '
          '${sequential ? 'sequential' : 'combinational'} assignments',
          () async {
        final module = MergedEnumPortAssignmentModule(Logic(width: 3),
            clock: sequential ? Logic() : null);
        final vectors = sequential
            ? [
                Vector({'source': 1, 'clock': 0}, {}),
                Vector({'clock': 1}, {'result': 1, 'mergedResult': 1}),
                Vector({'clock': 0}, {'result': 1, 'mergedResult': 1}),
                Vector({'source': 7}, {'result': 1, 'mergedResult': 1}),
                Vector({'clock': 1}, {'result': 7, 'mergedResult': 7}),
              ]
            : [
                for (final value in [1, 7, 1])
                  Vector({'source': value},
                      {'result': value, 'mergedResult': value}),
              ];
        await checkEnumModeParity(module, vectors);

        final sv = module.dumpSystemVerilog();
        final assignment = sequential ? '<=' : '=';
        expect(sv, contains('input logic [2:0] source'));
        expect(sv, contains('output logic [2:0] mergedResult'));
        expect(sv, contains("assign source_enum = TestEnum'(source);"));
        expect(sv, contains('storedState $assignment source_enum;'));
        expect(sv, contains('mergedResult_enum $assignment source_enum;'));
        expect(sv, contains('assign mergedResult = mergedResult_enum;'));

        for (final generateEnums in [true, false]) {
          SimCompare.checkVerilatorVector(module, const [],
              buildOnly: true,
              synthesizerConfiguration: SystemVerilogSynthesizerConfiguration(
                  generateEnums: generateEnums));
        }
      });
    }

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

    test('typed enum output survives child output concatenation', () async {
      final module = TypedEnumSplitOutputModule(Logic(width: 4));
      final vectors = [
        Vector({'source': 0}, {'stateOut': 0, 'other': 0}),
        Vector({'source': 5}, {'stateOut': 1, 'other': 1}),
        Vector({'source': 10}, {'stateOut': 2, 'other': 2}),
        Vector({'source': 9}, {'stateOut': 1, 'other': 2}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('.result({other,stateOut_enum})'));
      expect(sv, contains('assign stateOut = stateOut_enum;'));
      SimCompare.checkVerilatorVector(module, const [], buildOnly: true);
    });

    test('typed enum input survives packed connection selections', () async {
      final source = LogicEnum<TestEnum>.withMapping({
        TestEnum.a: 0,
        TestEnum.b: 10,
        TestEnum.c: 5,
      });
      final module = TypedEnumSliceInputModule(source);
      final vectors = [
        Vector({'stateIn': 0}, {'result': 0}),
        Vector({'stateIn': 10}, {'result': 3}),
        Vector({'stateIn': 5}, {'result': 4}),
      ];
      await checkEnumModeParity(module, vectors);

      final sv = module.dumpSystemVerilog();
      expect(sv, contains('stateIn_enum[2:1]'));
      expect(sv, contains('stateIn_enum[3]'));
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

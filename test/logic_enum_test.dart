//TODO: file headers

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
  late final Logic result;

  EnumCasesModule(Logic selector) {
    selector = addInput('selector', selector, width: 2);
    final enumSelector = MyListLogicEnum(name: 'enumSelector')..gets(selector);
    result = cases(enumSelector, {
      TestEnum.a: TestEnum.b,
      TestEnum.b: TestEnum.c,
      TestEnum.c: TestEnum.a,
    });
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

class EmptyModule extends Module {}

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

  test('conditional assignment validates known values and enum types', () {
    final logicEnum = LogicEnum(TestEnum.values);
    final incompatibleType = LogicEnum(OtherEnum.values);

    expect(() => logicEnum < 3, throwsA(isA<ArgumentError>()));
    expect(() => logicEnum < OtherEnum.a, throwsA(isA<ArgumentError>()));
    expect(() => logicEnum < incompatibleType, throwsA(isA<ArgumentError>()));
    expect(logicEnum < TestEnum.b, isA<Conditional>());
    expect(logicEnum < 2, isA<Conditional>());
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
    expect(SynthLogic.tryMerge(legalEnum, legalConstant), isNotNull);

    final illegalEnum = synth(LogicEnum(TestEnum.values));
    final illegalConstant = synth(Const(3, width: 2));
    expect(SynthLogic.tryMerge(illegalEnum, illegalConstant), isNull);
  });

  group('enum sv gen', () {
    test('simple mod with enum gen good sv', () async {
      final mod = SimpleModWithEnum(Logic(width: 3));
      await mod.build();

      final sv = mod.generateSynth();

      expect(
          sv,
          contains(
              "typedef enum logic [2:0] { a = 3'h1, c = 3'h7 } TestEnum;"));
      expect(sv, contains('TestEnum elephant;'));
    });

    test('conflicting enum mod gen good sv', () async {
      final mod = ConflictingEnumMod(Logic(width: 3));
      await mod.build();

      final sv = mod.generateSynth();

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

      final sv = mod.generateSynth();

      expect(
          sv,
          contains('typedef enum logic [1:0]'
              " { a = 2'h0, b = 2'h1, c = 2'h2 } TestEnum;"));
      expect(sv, contains('assign banana = carrot & b;'));
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

      final firstSv = module.generateSynth();
      final secondSv = module.generateSynth();

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
      final simpleSv = simpleModule.generateSynth(configuration: configuration);
      final constantSv =
          constantModule.generateSynth(configuration: configuration);
      final casesSv = casesModule.generateSynth(configuration: configuration);

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

    test('cases infers enum-valued results', () async {
      final module = EnumCasesModule(Logic(width: 2));
      await module.build();

      expect(module.result, isA<LogicEnum<TestEnum>>());
      expect(module.generateSynth(), contains("TestEnum'(selector)"));
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

      final sv = module.generateSynth();
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
      final untypedSv = module.generateSynth(configuration: configuration);
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

      final sv = module.generateSynth();
      expect(sv, contains("BroadEnum'(narrow)"));

      final vectors = [
        Vector({'selector': 0}, {'result': 0}),
        Vector({'selector': 1}, {'result': 1}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);

      const configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: false);
      final untypedSv = module.generateSynth(configuration: configuration);
      expect(untypedSv, isNot(contains('typedef enum')));
      expect(untypedSv, isNot(contains("BroadEnum'(")));
      SimCompare.checkIverilogVector(
        module,
        vectors,
        synthesizerConfiguration: configuration,
      );
    });

    test('enum with case and cond assignments', () async {
      final mod = ModWithCaseAndEnumCondAssign(Logic());
      await mod.build();

      final sv = mod.generateSynth();

      expect(sv, contains(' a : begin'));
      expect(sv, contains('nextState = a;'));
    });
  });
}

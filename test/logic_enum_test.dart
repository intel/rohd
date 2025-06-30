import 'package:rohd/rohd.dart';
import 'package:rohd/src/signals/signals.dart';
import 'package:test/test.dart';

enum TestEnum { a, b, c }

class MyListLogicEnum extends LogicEnum<TestEnum> {
  MyListLogicEnum({super.name}) : super(TestEnum.values);
}

class MyMapLogicEnum extends LogicEnum<TestEnum> {
  MyMapLogicEnum({super.name})
      : super.withMapping({
          TestEnum.a: 1,
          // TestEnum.b: 5, // `b` is not mapped!
          TestEnum.c: 7,
        }, width: 3);
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

void main() {
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
    // expect(() => e.valueEnum, throwsA(isA<RohdException>())); //TODO
  });

  test('enum puts with enums', () {
    final e = MyListLogicEnum()..put(TestEnum.b);
    expect(e.value.toInt(), TestEnum.b.index);
    expect(e.valueEnum, TestEnum.b);
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

      print(sv);

      // don't care which one has _0, but one of the does!
      expect(
          sv,
          contains(
              'typedef enum logic [2:0]' " { a = 3'h1, c = 3'h7 } TestEnum;"));
      expect(
          sv,
          contains('typedef enum logic [1:0]'
              " { a_0 = 2'h0, b = 2'h1, c_0 = 2'h2 } TestEnum_0;"));
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
  });
}

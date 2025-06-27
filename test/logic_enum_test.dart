import 'package:rohd/rohd.dart';
import 'package:rohd/src/signals/signals.dart';
import 'package:test/test.dart';

enum TestEnum { a, b, c }

class MyListLogicEnum extends LogicEnum<TestEnum> {
  MyListLogicEnum() : super(TestEnum.values);
}

class MyMapLogicEnum extends LogicEnum<TestEnum> {
  MyMapLogicEnum()
      : super.withMapping({
          TestEnum.a: 1,
          // TestEnum.b: 5, // `b` is not mapped!
          TestEnum.c: 7,
        }, width: 3);
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
    final e = MyListLogicEnum();
    e.put(TestEnum.b);
    expect(e.value.toInt(), TestEnum.b.index);
    expect(e.valueEnum, TestEnum.b);
  });
}

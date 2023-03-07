import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import '../chapter_3/full_adder.dart';

void main() {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'a', width: 8);

  final sum = nBitAdder(a, b);

  test('should return 10 when both input is 5', () {
    a.put(5);
    b.put(5);

    expect(sum.value.toInt(), equals(10));
  });
}

Logic nBitAdder(Logic a, Logic b) {
  assert(a.width == b.width, 'a and b should have same width.');

  Logic carry = Const(0);
  final sum = <Logic>[];

  for (var i = 0; i < a.width; i++) {
    final res = fullAdder(a[i], b[i], carry);
    carry = res.cOut;
    sum.add(res.sum);
  }

  sum.add(carry);

  return sum.rswizzle();
}

class FullAdderResult {
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'cOut');
}

// fullAdder function that has a return type of FullAdderResult
FullAdderResult fullAdder(Logic a, Logic b, Logic carryIn) {
  final and1 = carryIn & (a ^ b);
  final and2 = b & a;

  final res = FullAdderResult();
  res.sum <= (a ^ b) ^ carryIn;
  res.cOut <= and1 | and2;

  return res;
}

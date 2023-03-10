import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'a', width: 8);

  final sum = nBitAdder(a, b);

  test('should return 255 when both inputs are added', () {
    a.put(127);
    b.put(128);

    expect(sum.value.toInt(), equals(255));
  });
}

Logic nBitAdder(Logic a, Logic b) {
  assert(a.width == b.width, 'a and b should have same width.');

  final carry = Const(0);
  final sum = <Logic>[];

  recursiveFullAdder(a, b, carry, sum, 0);

  sum.add(carry);

  return sum.rswizzle();
}

void recursiveFullAdder(Logic a, Logic b, Logic carry, List<Logic> sum, int i) {
  // Base Case
  if (i == a.width) {
    // if the width equals to index 0
    return;
  } else {
    // Recursive Case
    final res = fullAdder(a[i], b[i], carry);
    // ignore: parameter_assignments
    recursiveFullAdder(a, b, res.cOut, sum, i + 1);
    sum.add(res.sum);
  }
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

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'b', width: 8);

  final diff = nBitSubtractor(a, b);

  test('should return 5 when a is 25 and b is 20', () {
    a.put(25);
    b.put(20);
    expect(diff.value.toInt(), equals(5));
  });
}

Logic nBitSubtractor(Logic a, Logic b) {
  assert(a.width == b.width, 'a and b should have same width.');

  Logic borrow = Const(0);
  final diff = <Logic>[];

  for (var i = 0; i < a.width; i++) {
    final res = rippleBorrowSubtractor(a[i], b[i], borrow);

    borrow = res.borrow;
    diff.add(res.diff);

    // print('i: $i, a: ${a[i].value.toInt()}, '
    //     'b: ${b[i].value.toInt()}, borrow: ${borrow.value.toInt()}, '
    //     'diff: ${res.diff.value.toInt()}, '
    //     'borrow: ${res.borrow.value.toInt()}');
  }
  diff.add(borrow);

  return diff.rswizzle();
}

FullSubtractorResult rippleBorrowSubtractor(Logic a, Logic b, Logic borrowIn) {
  final xorAB = a ^ b;

  final fsr = FullSubtractorResult();
  fsr.diff <= xorAB ^ borrowIn;
  fsr.borrow <= (~xorAB & borrowIn) | (~a & b);

  return fsr;
}

class FullSubtractorResult {
  final diff = Logic(name: 'diff');
  final borrow = Logic(name: 'borrow');
}

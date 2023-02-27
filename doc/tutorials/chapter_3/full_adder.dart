import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final cIn = Logic(name: 'c_in');

  // SUM
  final xorAB = a ^ b;
  final sum = xorAB ^ cIn;

  // C-Out
  final and1 = xorAB & cIn;
  final and2 = a & b;
  final cOut = and1 | and2;

  test('should return xor results correctly in a xor b.', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        a.put(i);
        b.put(j);

        expect(xorAB.value.toInt(), i == j ? 0 : 1);
      }
    }
  });

  test('should return true if result sum similar to truth table.', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        for (var k = 0; k <= 1; k++) {
          a.put(i);
          b.put(j);
          cIn.put(k);

          expect(sum.value.toInt(), faTruthTable(i, j, k).sum);
        }
      }
    }
  });

  test('should return true if result c-out is similar to truth table.',
      () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        for (var k = 0; k <= 1; k++) {
          a.put(i);
          b.put(j);
          cIn.put(k);

          expect(cOut.value.toInt(), faTruthTable(i, j, k).cOut);
        }
      }
    }
  });
}

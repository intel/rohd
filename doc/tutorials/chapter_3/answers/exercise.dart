import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() async {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final borrowIn = Logic(name: 'borrow_in');

  final xorAB = a ^ b;
  final diff = xorAB ^ borrowIn;
  final borrowOut = (~xorAB & borrowIn) | (~a & b);

  test('should return 0 when a and b equal 1', () async {
    a.put(1);
    b.put(1);
    borrowIn.put(0);

    expect(diff.value.toInt(), equals(0));
  });

  test('should return true if results matched truth table', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        for (var k = 0; k <= 1; k++) {
          a.put(i);
          b.put(j);
          borrowIn.put(k);

          final res = fsTruthTable(i, j, k);

          expect(diff.value.toInt(), res.diff);
          expect(borrowOut.value.toInt(), res.borrowOut);
        }
      }
    }
  });
}

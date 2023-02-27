import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final cIn = Logic(name: 'cIn');
  final sum = Logic(name: 'sum');

  final xorAB = a ^ b;

  test('should return xor results correctly in a xor b', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        a.put(i);
        b.put(j);
        expect(xorAB.value.toInt(), i == j ? 0 : 1);
      }
    }
  });
}

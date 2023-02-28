// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'helper.dart';

void faOps(Logic a, Logic b, Logic cIn, Logic xorAB, Logic sum, Logic cOut) {
  // SUM
  xorAB <= a ^ b;
  sum <= xorAB ^ cIn;

  // C-Out
  cOut <= xorAB & cIn | a & b;
}

void main() async {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final cIn = Logic(name: 'c_in');

  final xorAB = Logic(name: 'xor_ab');
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'cOut');

  faOps(a, b, cIn, xorAB, sum, cOut);

  test('should return xor results correctly in a xor b.', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        a.put(i);
        b.put(j);

        expect(xorAB.value.toBool(), i != j);
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

  final mod = FullAdderModule(a, b, cIn, faOps);
  await mod.build();

  print(mod.generateSynth());
}

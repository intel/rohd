// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import '../../chapter_3/answers/helper.dart';

class FullSubtractorResult {
  final diff = Logic(name: 'diff');
  final borrow = Logic(name: 'borrow');
}

class FullSubtractor extends Module {
  FullSubtractor(Logic a, Logic b, Logic borrowIn) {
    // Declare input and output
    a = addInput('a', a);
    b = addInput('b', b);
    borrowIn = addInput('borrowIn', borrowIn);

    final diff = addOutput('diff');
    final borrow = addOutput('borrow');

    // Logic
    final xorAB = a ^ b;

    diff <= xorAB ^ borrowIn;
    borrow <= (~xorAB & borrowIn) | (~a & b);
  }

  FullSubtractorResult get fsResult {
    final res = FullSubtractorResult();
    res.diff <= output('diff');
    res.borrow <= output('borrow');

    return res;
  }
}

Future<void> main() async {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final borrowIn = Logic();

  final diff = FullSubtractor(a, b, borrowIn);

  await diff.build();

  print(diff.generateSynth());

  test('should return true if results matched truth table', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        for (var k = 0; k <= 1; k++) {
          a.put(i);
          b.put(j);
          borrowIn.put(k);

          final res = fsTruthTable(i, j, k);

          final actualDiff = diff.fsResult.diff.value.toInt();
          final actualBorrowout = diff.fsResult.borrow.value.toInt();

          expect(actualDiff, res.diff);
          expect(actualBorrowout, res.borrowOut);
        }
      }
    }
  });
}

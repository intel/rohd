import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'helper.dart';

class FullSubtractor extends Module {
  FullSubtractor(Logic a, Logic b, Logic borrowIn)
      : super(name: 'full_subtractor') {
    // Add Input
    a = addInput('a', a);
    b = addInput('b', b);
    borrowIn = addInput('borrowIn', borrowIn);

    // Add Output
    final borrowOut = addOutput('borrowOut');
    final diff = addOutput('diff');

    // Logic
    final xorAB = a ^ b;
    diff <= xorAB ^ borrowIn;
    borrowOut <= (~xorAB & borrowIn) | (~a & b);
  }
  // getter for output
  Logic get borrowOut => output('borrowOut');
  Logic get diff => output('diff');
}

void main() async {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final borrowIn = Logic(name: 'borrow_in');

  final fSub = FullSubtractor(a, b, borrowIn);
  await fSub.build();

  // ignore: avoid_print
  print(fSub.generateSynth());

  test('should return 0 when a and b equal 1', () async {
    a.put(1);
    b.put(1);
    borrowIn.put(0);

    expect(fSub.diff.value.toInt(), equals(0));
  });

  test('should return true if results matched truth table', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        for (var k = 0; k <= 1; k++) {
          a.put(i);
          b.put(j);
          borrowIn.put(k);

          final res = fsTruthTable(i, j, k);

          expect(fSub.diff.value.toInt(), res.diff);
          expect(fSub.borrowOut.value.toInt(), res.borrowOut);
        }
      }
    }
  });
}

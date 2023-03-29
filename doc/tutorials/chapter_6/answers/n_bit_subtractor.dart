import 'dart:math';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../../chapter_3/answers/helper.dart';
import '../../chapter_5/answers/full_subtractor.dart';

class FullSubtractorComb extends FullSubtractor {
  @override
  FullSubtractorComb(super.a, super.b, super.borrowIn) {
    // Declare input and output
    final a = input('a');
    final b = input('b');
    final borrow = input('borrowIn');

    // results for combinational logic
    final diff = addOutput('diff_comb');
    final borrowOut = addOutput('borrow_comb');

    Combinational([
      Case([a, b, borrow].swizzle(), [
        CaseItem(Const(bin('000'), width: 3), [
          diff < 0,
          borrowOut < 0,
        ]),
        CaseItem(Const(bin('001'), width: 3), [
          diff < 1,
          borrowOut < 1,
        ]),
        CaseItem(Const(bin('010'), width: 3), [
          diff < 1,
          borrowOut < 1,
        ]),
        CaseItem(Const(bin('011'), width: 3), [
          diff < 0,
          borrowOut < 1,
        ]),
        CaseItem(Const(bin('100'), width: 3), [
          diff < 1,
          borrowOut < 0,
        ]),
        CaseItem(Const(bin('101'), width: 3), [
          diff < 0,
          borrowOut < 0,
        ]),
        CaseItem(Const(bin('110'), width: 3), [
          diff < 0,
          borrowOut < 0,
        ])
      ], defaultItem: [
        diff < 1,
        borrowOut < 1
      ])
    ]);
  }

  @override
  FullSubtractorResult get fsResult {
    final res = FullSubtractorResult();
    res.diff <= output('diff_comb');
    res.borrow <= output('borrow_comb');

    return res;
  }
}

class NBitFullSubtractor extends Module {
  NBitFullSubtractor(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final diff = addOutput('diff', width: a.width + b.width);

    Logic borrow = Const(0);
    final diffList = <Logic>[];

    for (var i = 0; i < a.width; i++) {
      final res = FullSubtractorComb(a[i], b[i], borrow);

      borrow = res.fsResult.borrow;
      diffList.add(res.fsResult.diff);
    }
    diffList.add(borrow);

    diff <= diffList.rswizzle().zeroExtend(diff.width);
  }

  // getter
  Logic get result => output('diff');
}

Future<void> main() async {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'b', width: 8);

  final mod = NBitFullSubtractor(a, b);
  await mod.build();

  // print(mod.generateSynth());

  group('Full Subtractor', () {
    test('should return True when cas conditionals matched truth table',
        () async {
      final a = Logic();
      final b = Logic();
      final bIn = Logic();

      final fsComb = FullSubtractorComb(a, b, bIn);
      await fsComb.build();

      for (var i = 0; i <= 1; i++) {
        for (var j = 0; j <= 1; j++) {
          for (var k = 0; k <= 1; k++) {
            a.put(i);
            b.put(j);
            bIn.put(k);

            final res = fsTruthTable(i, j, k);

            final actualDiff = fsComb.fsResult.diff.value.toInt();
            final actualBOut = fsComb.fsResult.borrow.value.toInt();

            final expectedDiff = res.diff;
            final expectedBOut = res.borrowOut;

            expect(actualDiff, expectedDiff,
                reason: 'a: $a, b: $b, bIn: $bIn'
                    ' actualDiff: $actualDiff, expectedDiff: $expectedDiff');

            expect(actualBOut, expectedBOut,
                reason: 'a: $a, b: $b, bIn: $bIn'
                    ' actualBOut: $actualBOut, expectedBOut: $expectedBOut');
          }
        }
      }
    });
  });

  test(
      'should return True when value of nbitsubtractor subtract a b '
      'is matched.', () async {
    final randA = Random().nextInt(10) + 10;
    final randB = Random().nextInt(10);
    final minusResult = randA - randB;

    final mod = NBitFullSubtractor(a, b);
    await mod.build();

    a.put(randA);
    b.put(randB);

    expect(mod.result.value.toInt(), equals(minusResult),
        reason: 'randA: $randA, randB: $randB, addResult: $minusResult');
  });
}

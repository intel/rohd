import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() async {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'b', width: 8);

  final mod = NBitSubtractor(a, b);
  await mod.build();
  print(mod.generateSynth());

  test('should return 5 when a is 25 and b is 20', () {
    a.put(25);
    b.put(20);
    expect(mod.diff.value.toInt(), equals(5));
  });
}

class NBitSubtractor extends Module {
  Logic get diff => output('diff');

  NBitSubtractor(Logic a, Logic b) {
    assert(a.width == b.width, 'a and b should have same width.');

    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final diff = addOutput('diff', width: 10);

    Logic borrow = Const(0);
    final diffList = <Logic>[];

    for (var i = 0; i < a.width; i++) {
      final res = FullSubtractor(a[i], b[i], borrow);

      borrow = res.result.borrow;
      diffList.add(res.result.diff);
    }
    diffList.add(borrow);

    diff <= diffList.rswizzle().zeroExtend(diff.width);
  }
}

class FullSubtractor extends Module {
  FullSubtractorResult get result {
    final res = FullSubtractorResult();
    res.diff <= output('diff');
    res.borrow <= output('borrowOut');

    return res;
  }

  FullSubtractor(Logic a, Logic b, Logic borrowIn) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    borrowIn = addInput('borrowIn', borrowIn);

    final diff = addOutput('diff');
    final borrowOut = addOutput('borrowOut');

    final xorAB = a ^ b;

    diff <= xorAB ^ borrowIn;
    borrowOut <= (~xorAB & borrowIn) | (~a & b);
  }
}

class FullSubtractorResult {
  final diff = Logic(name: 'diff');
  final borrow = Logic(name: 'borrow');
}

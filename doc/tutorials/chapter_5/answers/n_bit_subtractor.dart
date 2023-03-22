import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'full_subtractor.dart';

class NBitFullAdder extends Module {
  NBitFullAdder(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final diff = addOutput('diff', width: a.width + b.width);

    Logic borrow = Const(0);
    final diffList = <Logic>[];

    for (var i = 0; i < a.width; i++) {
      final res = FullSubtractor(a[i], b[i], borrow);

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

  final mod = NBitFullAdder(a, b);
  await mod.build();

  print(mod.generateSynth());

  test('should return 1 when a is 8 and b is 7.', () {
    a.put(8);
    b.put(7);

    expect(mod.result.value.toInt(), 1);
  });
}

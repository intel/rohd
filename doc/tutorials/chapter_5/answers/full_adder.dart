import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import '../../chapter_3/helper.dart';

class FullAdderResult {
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'c_out');
}

class FullAdder extends Module {
  final fullAdderresult = FullAdderResult();

  // Constructor
  FullAdder({
    required Logic a,
    required Logic b,
    required Logic carryIn,
    super.name = 'full_adder',
  }) {
    // Declare Input Node
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    carryIn = addInput('carry_in', carryIn, width: carryIn.width);

    // Declare Output Node
    final carryOut = addOutput('carry_out');
    final sum = addOutput('sum');

    final and1 = carryIn & (a ^ b);
    final and2 = b & a;

    sum <= (a ^ b) ^ carryIn;
    carryOut <= and1 | and2;

    fullAdderresult.sum <= output('sum');
    fullAdderresult.cOut <= output('carry_out');
  }

  FullAdderResult get fullAdderRes => fullAdderresult;
}

void main() async {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final cIn = Logic(name: 'cin');

  final mod = FullAdder(a: a, b: b, carryIn: cIn);
  await mod.build();

  print(mod.generateSynth());

  test('should return true if result sum similar to truth table.', () async {
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        for (var k = 0; k <= 1; k++) {
          a.put(i);
          b.put(j);
          cIn.put(k);

          final actual = mod.fullAdderRes.sum.value.toInt();

          expect(actual, faTruthTable(i, j, k).sum,
              reason: 'Input of a: $i, b: $j, cIn: $k; Output: $actual');
        }
      }
    }
  });
}

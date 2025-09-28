import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

// ignore_for_file: avoid_print, prefer_asserts_in_initializer_lists

void main() async {
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'a', width: 8);

  final mod = NBitAdder(a, b);
  await mod.build();

  print(mod.generateSynth());

  test('should return 255 when both inputs are added', () {
    a.put(127);
    b.put(128);

    expect(mod.sum.value.toInt(), equals(255));
  });
}

class NBitAdder extends Module {
  NBitAdder(Logic a, Logic b) {
    assert(a.width == b.width, 'a and b should have same width.');

    // add input
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    // add output
    final sum = addOutput('sum', width: a.width + b.width);

    final carry = Const(0);
    final sumContainer = <Logic>[];

    recursiveFullAdder(a, b, carry, sumContainer, 0);

    sumContainer.add(carry);

    sum <= sumContainer.rswizzle().zeroExtend(sum.width);
  }
  Logic get sum => output('sum');
}

void recursiveFullAdder(Logic a, Logic b, Logic carry, List<Logic> sum, int i) {
  // Base Case
  if (i == a.width) {
    // if the width equals to index 0
    return;
  } else {
    // Recursive Case
    final res = FullAdder(a[i], b[i], carry);
    recursiveFullAdder(a, b, res.result.cOut, sum, i + 1);
    sum.add(res.result.sum);
  }
}

class FullAdderResult {
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'cOut');
}

class FullAdder extends Module {
  FullAdder(Logic a, Logic b, Logic carryIn) {
    // Add Input
    a = addInput('a', a);
    b = addInput('b', b);
    carryIn = addInput('c', carryIn);

    // Add Output
    final sum = addOutput('sum');
    final cOut = addOutput('cOut');

    // Add Logic
    final and1 = carryIn & (a ^ b);
    final and2 = b & a;

    sum <= (a ^ b) ^ carryIn;
    cOut <= and1 | and2;
  }

  FullAdderResult get result {
    final res = FullAdderResult();
    res.sum <= output('sum');
    res.cOut <= output('cOut');

    return res;
  }
}

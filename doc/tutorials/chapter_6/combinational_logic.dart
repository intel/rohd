import 'dart:math';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../chapter_3/helper.dart';
import 'case.dart';
import 'if_block.dart';

class FullAdderResult {
  final sum = Logic(name: 'sum');
  final cOut = Logic(name: 'c_out');
}

enum FACond { ifblock, caseBlock }

class FullAdder extends Module {
  // Constructor
  FullAdder({
    required Logic a,
    required Logic b,
    required Logic carryIn,
    FACond selection = FACond.ifblock,
    super.name = 'full_adder',
  }) {
    // Declare Input Node
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    carryIn = addInput('carry_in', carryIn, width: carryIn.width);

    // Declare Output Node
    final carryOut = addOutput('carry_out');
    final sum = addOutput('sum');

    if (selection == FACond.ifblock) {
      Combinational([truthTableIf(a, b, carryIn, sum, carryOut)]);
    } else {
      Combinational([truthTableCase(a, b, carryIn, sum, carryOut)]);
    }
  }

  FullAdderResult get fullAdderRes {
    final fullAdderresult = FullAdderResult();
    fullAdderresult.sum <= output('sum');
    fullAdderresult.cOut <= output('carry_out');

    return fullAdderresult;
  }
}

class NBitAdder extends Module {
  // Add Input and output port
  final sum = <Logic>[];
  Logic carry = Const(0);
  Logic a;
  Logic b;

  NBitAdder(this.a, this.b) {
    // Declare Input Node
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    carry = addInput('carry_in', carry, width: carry.width);

    final n = a.width;
    FullAdder? res;

    assert(a.width == b.width, 'a and b should have same width.');

    for (var i = 0; i < n; i++) {
      res = FullAdder(a: a[i], b: b[i], carryIn: carry);

      carry = res.fullAdderRes.cOut;
      sum.add(res.fullAdderRes.sum);
    }

    sum.add(carry);
  }

  LogicValue get sumRes => sum.rswizzle().value;
}

void main() async {
  group('full adder', () {
    test(
        'should return true if result sum similar to truth table when using '
        'If as conditionals.', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final cIn = Logic(name: 'carry_in');

      final fullAdder = FullAdder(a: a, b: b, carryIn: cIn);
      await fullAdder.build();

      for (var i = 0; i <= 1; i++) {
        for (var j = 0; j <= 1; j++) {
          for (var k = 0; k <= 1; k++) {
            a.put(i);
            b.put(j);
            cIn.put(k);

            expect(fullAdder.fullAdderRes.sum.value.toInt(),
                faTruthTable(i, j, k).sum,
                reason: 'a: $i, b: $j, c: $k');
          }
        }
      }
    });
    test(
        'should return true if result sum similar to truth table when using '
        'Case as conditionals.', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final cIn = Logic(name: 'carry_in');

      final fullAdder =
          FullAdder(a: a, b: b, carryIn: cIn, selection: FACond.caseBlock);
      await fullAdder.build();

      for (var i = 0; i <= 1; i++) {
        for (var j = 0; j <= 1; j++) {
          for (var k = 0; k <= 1; k++) {
            a.put(i);
            b.put(j);
            cIn.put(k);

            expect(fullAdder.fullAdderRes.sum.value.toInt(),
                faTruthTable(i, j, k).sum,
                reason: 'a: $i, b: $j, c: $k');
          }
        }
      }
    });
  });

  group('nBitAdder', () {
    test('should return correct results when nbitadder A and B perform add.',
        () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);

      final nbitAdder = NBitAdder(a, b);
      await nbitAdder.build();

      final randA = Random().nextInt(10);
      final randB = Random().nextInt(10);
      final addResult = randA + randB;

      a.put(randA);
      b.put(randB);

      expect(nbitAdder.sumRes.toInt(), equals(addResult),
          reason: 'randA: $randA, randB: $randB, addResult: $addResult');
    });
  });
}

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

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

    // Use Combinational block
    Combinational([
      sum < (a ^ b) ^ carryIn,
      carryOut < and1 | and2,
    ]);

    fullAdderresult.sum <= output('sum');
    fullAdderresult.cOut <= output('carry_out');
  }

  FullAdderResult get fullAdderRes => fullAdderresult;
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
  final a = Logic(name: 'a', width: 8);
  final b = Logic(name: 'b', width: 8);
  final nbitAdder = NBitAdder(a, b);

  await nbitAdder.build();

  // print(nbitAdder.generateSynth());

  test('should return 20 when A and B perform add.', () async {
    a.put(15);
    b.put(5);

    expect(nbitAdder.sumRes.toInt(), equals(20));
  });
}

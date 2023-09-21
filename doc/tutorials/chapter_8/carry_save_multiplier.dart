// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import '../chapter_5/n_bit_adder.dart';

class CarrySaveMultiplier extends Module {
  // Add Input and output port for FA sum and Carry
  final List<Logic> sum =
      List.generate(8, (index) => Logic(name: 'sum_$index'));
  final List<Logic> carry =
      List.generate(8, (index) => Logic(name: 'carry_$index'));

  late final Pipeline pipeline;
  CarrySaveMultiplier(Logic valA, Logic valB, Logic clk, Logic reset,
      {super.name = 'carry_save_multiplier'}) {
    // Declare Input Node
    valA = addInput('a', valA, width: valA.width);
    valB = addInput('b', valB, width: valB.width);
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    final product = addOutput('product', width: valA.width + valB.width + 1);
    final rCarryA = Logic(name: 'rcarry_a', width: valA.width);
    final rCarryB = Logic(name: 'rcarry_b', width: valB.width);

    pipeline = Pipeline(
      clk,
      stages: [
        ...List.generate(
          valB.width,
          (row) => (p) {
            final columnAdder = <Conditional>[];
            final maxIndexA = (valA.width - 1) + row;

            for (var column = maxIndexA; column >= row; column--) {
              final fullAdder = FullAdder(
                      a: column == maxIndexA || row == 0
                          ? Const(0)
                          : p.get(sum[column]),
                      b: p.get(valA)[column - row] & p.get(valB)[row],
                      carryIn: row == 0 ? Const(0) : p.get(carry[column - 1]))
                  .fullAdderRes;

              columnAdder
                ..add(p.get(carry[column]) < fullAdder.cOut)
                ..add(p.get(sum[column]) < fullAdder.sum);
            }

            return columnAdder;
          },
        ),
        (p) => [
              p.get(rCarryA) <
                  <Logic>[
                    Const(0),
                    ...List.generate(
                        valA.width - 1,
                        (index) =>
                            p.get(sum[(valA.width + valB.width - 2) - index]))
                  ].swizzle(),
              p.get(rCarryB) <
                  <Logic>[
                    ...List.generate(
                        valA.width,
                        (index) =>
                            p.get(carry[(valA.width + valB.width - 2) - index]))
                  ].swizzle()
            ],
      ],
      reset: reset,
      resetValues: {product: Const(0)},
    );

    final nBitAdder = NBitAdder(
      pipeline.get(rCarryA),
      pipeline.get(rCarryB),
    );

    product <=
        <Logic>[
          ...List.generate(
            valA.width + 1,
            (index) => nBitAdder.sum[(valA.width) - index],
          ),
          ...List.generate(
            valA.width,
            (index) => pipeline.get(sum[valA.width - index - 1]),
          )
        ].swizzle();
  }

  Logic get product => output('product');
}

void main() async {
  final a = Logic(name: 'a', width: 4);
  final b = Logic(name: 'b', width: 4);
  final reset = Logic(name: 'reset');
  final clk = SimpleClockGenerator(10).clk;

  final csm = CarrySaveMultiplier(a, b, clk, reset);

  await csm.build();

  // after one cycle, change the value of a and b
  a.inject(10);
  b.inject(14);
  reset.inject(1);

  // Attach a waveform dumper so we can see what happens.
  WaveDumper(csm, outputPath: 'csm.vcd');

  Simulator.registerAction(10, () {
    reset.inject(0);
  });

  Simulator.registerAction(30, () {
    a.put(10);
    b.put(11);
  });

  Simulator.registerAction(60, () {
    a.put(10);
    b.put(6);
  });

  csm.product.changed.listen((event) {
    print('@t=${Simulator.time}, product is: ${event.newValue.toInt()}');
  });

  Simulator.setMaxSimTime(150);

  await Simulator.run();
}

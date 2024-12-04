import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('async reset samples correct reset value', () {
    final seqMechanism = {
      'Sequential.multi': (Logic clk, Logic reset, Logic val) =>
          Sequential.multi(
            [clk, reset],
            reset: reset,
            [
              val < 1,
            ],
          ),
      'Sequential with asyncReset': (Logic clk, Logic reset, Logic val) =>
          Sequential(
            clk,
            reset: reset,
            [
              val < 1,
            ],
            asyncReset: true,
          ),
      'FlipFlop with asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            FlipFlop(
              clk,
              reset: reset,
              val,
              asyncReset: true,
            ).q;
      },
      'flop with asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            flop(
              clk,
              reset: reset,
              val,
              asyncReset: true,
            );
      },
    };

    for (final mechanism in seqMechanism.entries) {
      test('using ${mechanism.key}', () async {
        final clk = Logic(name: 'clk');
        final reset = Logic(name: 'reset');
        final val = Logic(name: 'val');

        reset.inject(0);
        clk.inject(0);

        mechanism.value(clk, reset, val);

        Simulator.registerAction(10, () {
          clk.put(1);
        });

        Simulator.registerAction(14, () {
          reset.put(1);
        });

        Simulator.registerAction(15, () {
          expect(val.value.toInt(), 0);
        });

        await Simulator.run();
      });
    }
  });

  //TODO: test async reset with clocks too
}

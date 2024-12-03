import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('async reset samples correct reset value', () async {
    final clk = Logic();
    final reset = Logic();
    final val = Logic();

    reset.inject(0);
    clk.inject(0);

    //TODO: try different ways to define the reset as async
    Sequential.multi(
      [clk, reset],
      reset: reset,
      [
        val < 1,
      ],
    );

    Simulator.registerAction(10, () {
      clk.inject(1);
    });

    Simulator.registerAction(14, () {
      reset.inject(1);
    });

    Simulator.registerAction(15, () {
      expect(val.value.toInt(), 0);
    });

    await Simulator.run();
  });
}

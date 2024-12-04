import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('async reset samples correct reset value', () async {
    final clk = Logic(name: 'clk');
    final reset = Logic(name: 'reset');
    final val = Logic(name: 'val');

    reset.glitch.listen((x) => print('reset: $x'));

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

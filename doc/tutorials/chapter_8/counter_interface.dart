// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

enum CounterDirection { inward, outward, misc }

/// A simple [Interface] for [Counter].
class CounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');
  Logic get clk => port('clk');

  final int width;
  CounterInterface({this.width = 8}) {
    setPorts([
      Port('en'),
      Port('reset'),
    ], [
      CounterDirection.inward
    ]);

    setPorts([
      Port('val', width),
    ], [
      CounterDirection.outward
    ]);

    setPorts([
      Port('clk'),
    ], [
      CounterDirection.misc
    ]);
  }
}

/// A simple counter which increments once per [clk] edge whenever
/// [en] is high, and [reset]s to 0, with output [val].
class Counter extends Module {
  Logic get clk => input('clk');
  Logic get en => input('en');
  Logic get reset => input('reset');
  Logic get val => output('val');

  late final CounterInterface intf;

  Counter(CounterInterface intf) : super(name: 'counter') {
    this.intf = CounterInterface(width: intf.width)
      ..connectIO(this, intf,
          inputTags: {CounterDirection.inward, CounterDirection.misc},
          outputTags: {CounterDirection.outward});

    final nextVal = Logic(name: 'nextVal', width: intf.width);

    nextVal <= intf.val + 1;

    Sequential(intf.clk, [
      If(intf.reset, then: [
        intf.val < 0
      ], orElse: [
        If(
          intf.en,
          then: [intf.val < nextVal],
        )
      ])
    ]);
  }
}

Future<void> main() async {
  final intf = CounterInterface();
  intf.clk <= SimpleClockGenerator(10).clk;

  final counter = Counter(intf);

  intf.en.inject(0);
  intf.reset.inject(1);

  await counter.build();

  print(counter.generateSynth());

  WaveDumper(counter,
      outputPath: 'doc/tutorials/chapter_8/counter_interface.vcd');
  Simulator.registerAction(25, () {
    intf.en.put(1);
    intf.reset.put(0);
  });

  Simulator.setMaxSimTime(100);

  await Simulator.run();
}

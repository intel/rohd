// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

enum CounterDirection { inward, outward, misc }

class CounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');
  Logic get clk => port('clk');

  final int width;
  CounterInterface({this.width = 8}) {
    setPorts([
      Logic.port('en'),
      Logic.port('reset'),
    ], [
      CounterDirection.inward
    ]);

    setPorts([
      Logic.port('val', width),
    ], [
      CounterDirection.outward
    ]);

    setPorts([
      Logic.port('clk'),
    ], [
      CounterDirection.misc
    ]);
  }

  @override
  CounterInterface clone() => CounterInterface(width: width);
}

class Counter extends Module {
  late final CounterInterface _intf;

  Counter(CounterInterface intf) : super(name: 'counter') {
    _intf = connectInterface(intf,
        inputTags: {CounterDirection.inward, CounterDirection.misc},
        outputTags: {CounterDirection.outward});

    final nextVal = Logic(name: 'nextVal', width: intf.width);

    nextVal <= _intf.val + 1;

    Sequential(_intf.clk, [
      If.block([
        Iff(_intf.reset, [
          _intf.val < 0,
        ]),
        ElseIf(_intf.en, [
          _intf.val < nextVal,
        ])
      ]),
    ]);
  }
}

Future<void> main() async {
  final intf = CounterInterface();
  intf.clk <= SimpleClockGenerator(10).clk;
  intf.en.inject(0);
  intf.reset.inject(1);

  final counter = Counter(intf);

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

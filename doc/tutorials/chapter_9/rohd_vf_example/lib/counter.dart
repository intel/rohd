import 'package:rohd/rohd.dart';

enum CounterDirection { inward, outward, misc }

/// A simple [Interface] for [MyCounter].
class MyCounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');
  Logic get clk => port('clk');

  final int width;
  MyCounterInterface({this.width = 8}) {
    setPorts(
        [Logic.port('en'), Logic.port('reset')], [CounterDirection.inward]);

    setPorts([
      Logic.port('val', width),
    ], [
      CounterDirection.outward
    ]);

    setPorts([Logic.port('clk')], [CounterDirection.misc]);
  }

  @override
  MyCounterInterface clone() => MyCounterInterface(width: width);
}

/// A simple counter which increments once per [clk] edge whenever
/// [en] is high, and [reset]s to 0, with output [val].
class MyCounter extends Module {
  Logic get clk => input('clk');
  Logic get en => input('en');
  Logic get reset => input('reset');
  Logic get val => output('val');

  late final MyCounterInterface counterintf;

  MyCounter(MyCounterInterface intf) : super(name: 'counter') {
    counterintf = connectInterface(counterintf,
        inputTags: {CounterDirection.inward, CounterDirection.misc},
        outputTags: {CounterDirection.outward});

    _buildLogic();
  }

  void _buildLogic() {
    final nextVal = Logic(name: 'nextVal', width: counterintf.width);

    nextVal <= counterintf.val + 1;

    Sequential(clk, [
      If(reset, then: [
        counterintf.val < 0
      ], orElse: [
        If(en, then: [counterintf.val < nextVal])
      ])
    ]);
  }
}

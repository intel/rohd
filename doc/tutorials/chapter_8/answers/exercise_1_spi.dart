// ignore_for_file: avoid_print

import 'dart:async';

import 'package:rohd/rohd.dart';

// Define a set of legal directions for SPI interface, will
// be pass as parameter to Interface
enum SPIDirection { controllerOutput, peripheralOutput }

// Create an interface for Serial Peripheral Interface
class SPIInterface extends Interface<SPIDirection> {
  // include the getter to the function
  Logic get sck => port('sck'); // serial clock
  Logic get sdi => port('sdi'); // serial data in (mosi)
  Logic get sdo => port('sdo'); // serial data out (miso)
  Logic get cs => port('cs'); // chip select

  SPIInterface() {
    // Output from Controller, Input to Peripheral
    setPorts([
      Logic.port('sck'),
      Logic.port('sdi'),
      Logic.port('cs'),
    ], [
      SPIDirection.controllerOutput
    ]);

    // Output from Peripheral, Input to Controller
    setPorts([
      Logic.port('sdo'),
    ], [
      SPIDirection.peripheralOutput
    ]);
  }

  @override
  SPIInterface clone() => SPIInterface();
}

class Controller extends Module {
  late final Logic _reset;
  late final Logic _sin;

  Controller(SPIInterface intf, Logic reset, Logic sin)
      : super(name: 'controller') {
    // set input port to private variable instead,
    // we don't want other class to access this
    _reset = addInput('reset', reset);
    _sin = addInput('sin', sin);

    // define a new interface, and connect it
    // to the interface passed in.
    intf = SPIInterface()
      ..connectIO(
        this,
        intf,
        inputTags: {SPIDirection.peripheralOutput}, // Add inputs
        outputTags: {SPIDirection.controllerOutput}, // Add outputs
      );

    intf.cs <= Const(1);

    Sequential(intf.sck, [
      If.block([
        Iff(_reset, [
          intf.sdi < 0,
        ]),
        Else([
          intf.sdi < _sin,
        ]),
      ])
    ]);
  }
}

class Peripheral extends Module {
  Logic get sck => input('sck');
  Logic get sdi => input('sdi');
  Logic get cs => input('cs');

  Logic get sdo => output('sdo');
  Logic get sout => output('sout');

  late final SPIInterface shiftRegIntF;

  Peripheral(SPIInterface periIntF) : super(name: 'shift_register') {
    shiftRegIntF = SPIInterface()
      ..connectIO(
        this,
        periIntF,
        inputTags: {SPIDirection.controllerOutput},
        outputTags: {SPIDirection.peripheralOutput},
      );

    const regWidth = 8;
    final data = Logic(name: 'data', width: regWidth);
    final sout = addOutput('sout', width: 8);

    Sequential(sck, [
      If(shiftRegIntF.cs, then: [
        data < [data.slice(regWidth - 2, 0), sdi].swizzle()
      ], orElse: [
        data < 0
      ])
    ]);

    sout <= data;
    shiftRegIntF.sdo <= data.getRange(0, 1);
  }
}

class TestBench extends Module {
  Logic get sout => output('sout');

  final spiInterface = SPIInterface();
  final clk = SimpleClockGenerator(10).clk;

  TestBench(Logic reset, Logic sin) {
    reset = addInput('reset', reset);
    sin = addInput('sin', sin);

    final sout = addOutput('sout', width: 8);

    // ignore: unused_local_variable
    final ctrl = Controller(spiInterface, reset, clk);
    final peripheral = Peripheral(spiInterface);

    sout <= peripheral.sout;
  }
}

void main() async {
  final testInterface = SPIInterface();
  testInterface.sck <= SimpleClockGenerator(10).clk;

  final peri = Peripheral(testInterface);
  await peri.build();

  final reset = Logic();
  final sin = Logic();
  final tb = TestBench(reset, sin);

  await tb.build();

  print(tb.generateSynth());

  testInterface.cs.inject(0);
  testInterface.sdi.inject(0);

  void printFlop([String message = '']) {
    print('@t=${Simulator.time}:\t'
        ' input=${testInterface.sdi.value}, output '
        '=${peri.sout.value.toString(includeWidth: false)}\t$message');
  }

  Future<void> drive(LogicValue val) async {
    for (var i = 0; i < val.width; i++) {
      peri.cs.put(1);
      peri.sdi.put(val[i]);
      await peri.sck.nextPosedge;

      printFlop();
    }
  }

  Simulator.setMaxSimTime(100);
  unawaited(Simulator.run());

  WaveDumper(peri, outputPath: 'doc/tutorials/chapter_8/spi-new.vcd');

  await drive(LogicValue.ofString('01010101'));
}

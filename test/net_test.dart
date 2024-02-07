import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SubModWithInout extends Module {
  SubModWithInout(Logic isDriver, Logic toDrive, Logic io)
      : super(name: 'submodwithinout') {
    isDriver = addInput('isDriver', isDriver);
    toDrive = addInput('toDrive', toDrive, width: toDrive.width);
    io = addInOut('io', io, width: toDrive.width);

    io <= TriStateBuffer(toDrive, enable: isDriver).out;
  }
}

class TopModWithDrivers extends Module {
  Logic get drivenValue => output('drivenValue');
  TopModWithDrivers(Logic driverSelect) : super(name: 'topmodwdrivers') {
    driverSelect = addInput('driverSelect', driverSelect);

    final driveable = LogicNet(
      width: 8,
      name: 'driveable',
      naming: Naming.mergeable,
    );

    SubModWithInout(driverSelect, Const(0xaa, width: 8), driveable);
    SubModWithInout(~driverSelect, Const(0x55, width: 8), driveable);

    addOutput('drivenValue', width: 8) <= driveable;
  }
}

//TODO: test when there are multiple assignments with named wires nets, bidirectional assignment behavior
//TODO: test driving and being driven by structs, arrays
//TODO: test module hierarchy searching with only inouts

void main() {
  test('simple tristate', () async {
    final driverSelect = Logic();
    final mod = TopModWithDrivers(driverSelect);
    await mod.build();

    driverSelect.put(1);
    print(mod.drivenValue.value);

    print(mod.generateSynth());
  });

  test('simple tristate simcompare', () async {
    final mod = TopModWithDrivers(Logic());
    await mod.build();

    final vectors = [
      Vector({'driverSelect': 0}, {'drivenValue': 0x55}),
      Vector({'driverSelect': 1}, {'drivenValue': 0xaa}),
      Vector({'driverSelect': LogicValue.z}, {'drivenValue': LogicValue.x}),
      Vector({'driverSelect': LogicValue.x}, {'drivenValue': LogicValue.x}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);

    // print(mod.generateSynth());
  });
}

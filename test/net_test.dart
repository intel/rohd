import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SubModWithInout extends Module {
  SubModWithInout(Logic isDriver, Logic toDrive, LogicNet io)
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
//TODO: test `changed` on nets

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('basic net connection', () {
    final a = LogicNet(name: 'a');
    final b = LogicNet(name: 'b');

    a <= b;

    expect(b.value, LogicValue.z);
    expect(a.value, LogicValue.z);

    a.put(1);

    expect(b.value.toInt(), 1);
    expect(a.value.toInt(), 1);

    b.put(0);

    expect(b.value.toInt(), 0);
    expect(a.value.toInt(), 0);

    a.put(LogicValue.z);

    expect(b.value, LogicValue.z);
    expect(a.value, LogicValue.z);
  });

  test('basic net with logic drivers', () {
    final a = Logic(name: 'a');
    final b = Logic(name: 'b');

    final n = LogicNet(name: 'n');

    n <= a;
    n <= b;

    expect(a.value, LogicValue.z);
    expect(b.value, LogicValue.z);
    expect(n.value, LogicValue.z);

    a.put(1);

    expect(a.value.toInt(), 1);
    expect(b.value, LogicValue.z);
    expect(n.value.toInt(), 1);

    b.put(0);

    expect(a.value.toInt(), 1);
    expect(b.value.toInt(), 0);
    expect(n.value, LogicValue.x);

    a.put(LogicValue.z);

    expect(a.value, LogicValue.z);
    expect(b.value.toInt(), 0);
    expect(n.value.toInt(), 0);
  });

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

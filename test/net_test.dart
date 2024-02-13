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

class SubModInoutOnly extends Module {
  SubModInoutOnly({LogicNet? inio, LogicNet? outio}) : super(name: 'submod') {
    final internalio = LogicNet(name: 'internalio');
    if (inio != null) {
      internalio <= addInOut('inio', inio);
    }
    if (outio != null) {
      addInOut('outio', outio) <= internalio;
    }
  }
}

class TopModConnectivity extends Module {
  TopModConnectivity({LogicNet? inio, LogicNet? outio, LogicNet? io}) {
    if (io != null) {
      io = addInOut('io', io);
    }

    if (inio != null) {
      inio = addInOut('inio', inio);
    }

    if (inio != null || io != null) {
      SubModInoutOnly(inio: inio, outio: io);
    }

    if (outio != null) {
      outio = addInOut('outio', outio);
    }

    if (outio != null || io != null) {
      SubModInoutOnly(outio: outio, inio: io);
    }
  }
}

//TODO: test when there are multiple assignments with named wires nets, bidirectional assignment behavior
//TODO: test driving and being driven by structs, arrays
//TODO: test module hierarchy searching with only inouts
//TODO: test `changed` on nets
//TODO: test driving from an always_comb/always_ff to make sure a separate assignment is generated

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

    expect(mod.drivenValue.value.toInt(), 0xaa);
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
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('io only hier', () {
    test('all ios', () async {
      final mod = TopModConnectivity(
        inio: LogicNet(),
        outio: LogicNet(),
        io: LogicNet(),
      );

      await mod.build();

      final vectors = [
        Vector({'inio': 0}, {'outio': 0, 'io': 0}),
        Vector({'inio': 1}, {'outio': 1, 'io': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('in io only', () async {
      final mod = TopModConnectivity(
        inio: LogicNet(),
      );

      await mod.build();

      final sv = mod.generateSynth();
      expect('SubModInoutOnly  submod'.allMatches(sv).length, 1);
    });

    test('out io only', () async {
      final mod = TopModConnectivity(
        outio: LogicNet(),
      );

      await mod.build();

      final sv = mod.generateSynth();
      expect('SubModInoutOnly  submod'.allMatches(sv).length, 1);
    });

    test('mid io only', () async {
      final mod = TopModConnectivity(
        io: LogicNet(),
      );

      await mod.build();

      final sv = mod.generateSynth();
      expect('  submod'.allMatches(sv).length, 2);
    });
  });
}

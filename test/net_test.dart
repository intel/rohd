import 'package:collection/collection.dart';
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

class BidirectionalAssignmentMod extends Module {
  BidirectionalAssignmentMod(Logic control,
      {required bool directionBackwards}) {
    control = addInput('control', control);

    final result = addInOut('result', LogicNet(width: 8), width: 8);

    final intermediate = LogicNet(name: 'intermediate', width: 8);

    intermediate <= TriStateBuffer(Const(0x55, width: 8), enable: control).out;
    TriStateBuffer(Const(0xaa, width: 8), enable: ~control).out <= intermediate;

    if (directionBackwards) {
      intermediate <= result;
    } else {
      result <= intermediate;
    }
  }
}

enum NetTag { na, nb }

class NetIntf extends Interface<NetTag> {
  NetIntf() {
    setPorts([LogicNet.port('ana', 8)], {NetTag.na});
    setPorts([LogicNet.port('anb', 8)], {NetTag.nb});
  }
}

class NetISubMod extends Module {
  NetISubMod(Logic norm, LogicNet net, NetIntf intf, NetTag drive)
      : super(
            name: 'submod_${drive.name}',
            definitionName: 'NetISubMod_${drive.name}') {
    norm = addInput('inNorm', norm, width: 8);
    net = addInOut('inNet', net, width: 8);

    intf = NetIntf()..connectIO(this, intf, inOutTags: [drive]);

    final internal = LogicNet(name: 'internal', width: 8);
    internal <= [norm.getRange(0, 4), net.getRange(0, 4)].swizzle();

    intf.getPorts([drive]).values.first <= internal;
  }
}

class NetITopMod extends Module {
  NetITopMod(Logic x, NetIntf intf) : super(name: 'itop') {
    x = addInput('x', x, width: 8);

    final net = LogicNet(width: 8, name: 'myNet');
    final norm = LogicNet(width: 8, name: 'myNorm');

    // ignore: parameter_assignments
    intf = NetIntf()..connectIO(this, intf, outputTags: NetTag.values);

    NetISubMod(norm, net, intf, NetTag.na);
    NetISubMod(net, norm, intf, NetTag.nb);

    net <= ~x;
    norm <= x;
  }
}

enum NetArrayTag { d2, d3 }

class NetArrayIntf extends Interface<NetArrayTag> {
  NetArrayIntf() {
    setPorts([
      LogicArray.netPort('ad2', [2], 8)
    ], {
      NetArrayTag.d2
    });

    setPorts([
      LogicArray.netPort('bd3', [2, 2], 8)
    ], {
      NetArrayTag.d3
    });
  }
}

class NetArraySubMod extends Module {
  NetArraySubMod(NetArrayIntf intf, LogicArray in4net, LogicArray in4normal,
      NetArrayTag drive)
      : super(
            name: 'net_array_submod_inst_${drive.name}',
            definitionName: 'net_array_submod_${drive.name}') {
    in4net = addInOutArray(
      'in4net',
      in4net,
      dimensions: [3],
      elementWidth: 8,
    );

    in4normal = addInOutArray(
      'in4normal',
      in4net,
      dimensions: [3],
      elementWidth: 8,
    );

    intf = NetArrayIntf()..connectIO(this, intf, inOutTags: [drive]);

    final drivePort = intf.getPorts([drive]).values.first as LogicArray;
    for (var i = 0; i < drivePort.leafElements.length; i++) {
      if (i.isEven) {
        drivePort.leafElements[i] <= in4net.elements[i % 3];
      } else {
        drivePort.leafElements[i] <= in4normal.elements[i % 3];
      }
    }
  }
}

class NetArrayTopMod extends Module {
  NetArrayTopMod(Logic x, NetArrayIntf intf) {
    x = addInput('x', x, width: 8);

    final net = LogicArray.net([3], 8, name: 'myNet');
    final norm = LogicArray([3], 8, name: 'myNorm');
    intf = NetArrayIntf()
      ..connectIO(this, intf, outputTags: NetArrayTag.values);

    for (final element in net.elements) {
      element <= ~x;
    }
    for (final element in norm.elements) {
      element <= x;
    }

    NetArraySubMod(intf, net, norm, NetArrayTag.d2);
    NetArraySubMod(intf, norm, net, NetArrayTag.d3);
  }
}

//TODO: test when there are multiple assignments with named wires nets, bidirectional assignment behavior
//TODO: test driving and being driven by structs, arrays
//TODO: test module hierarchy searching with only inouts
//TODO: test `changed` on nets
//TODO: test driving from an always_comb/always_ff to make sure a separate assignment is generated
//TODO: test gate operations on nets (like binary operations & |), keep an eye out for wire name inlineing? shouldnt happen if feeding into a wire port!
//TODO: test build when misconnected inout (without a port)

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

  group('bidirectional assignments', () {
    for (final driveBackwards in [true, false]) {
      test('drive backwards = $driveBackwards', () async {
        final mod = BidirectionalAssignmentMod(Logic(),
            directionBackwards: driveBackwards);
        await mod.build();

        final vectors = [
          Vector({'control': 1}, {'result': 0x55}),
          Vector({'control': 0}, {'result': 0xaa}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors, dontDeleteTmpFiles: true);
      });
    }
  });

  test('hier with intfs for nets', () async {
    final mod = NetITopMod(Logic(width: 8), NetIntf());
    await mod.build();

    // test that internal signals contains myNorm and myNet
    for (final expectedInternal in ['myNorm', 'myNet']) {
      expect(
          mod.internalSignals
              .firstWhereOrNull((element) => element.name == expectedInternal),
          isNotNull);
    }

    final sv = mod.generateSynth();

    // test that " _b;" is not present (indication that a leftover internal
    // signal was there)
    expect(sv.contains(' _b;'), isFalse);

    final vectors = [
      Vector({'x': 0xaa}, {'ana': 0xa5, 'anb': 0x5a})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors, dontDeleteTmpFiles: true);
  });

  group('net arrays', () {
    test('simple build', () async {
      final mod = NetArrayTopMod(Logic(width: 8), NetArrayIntf());
      await mod.build();

      // mod.internalSignals.forEach(print);
      // print('--');
      // mod.subModules.forEach((element) {
      //   element.internalSignals.forEach(print);
      //   print('--');
      // });

      print(mod.hierarchyString());

      final sv = mod.generateSynth();
      print(sv);
      // expect(sv, contains('wire [1:0][7:0] bd3 [1:0];'));
    });

    test('connections and build', () async {
      final mod = NetArrayTopMod(Logic(width: 8), NetArrayIntf());
      await mod.build();

      final vectors = [
        Vector({'x': 0xaa}, {'ad2': 0xaa55, 'bd3': 0xaa55aa55})
      ];

      // await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors, dumpWaves: true);
    });
  });
}

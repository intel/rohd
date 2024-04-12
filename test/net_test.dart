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

class MultipleNamedIntermediates extends Module {
  MultipleNamedIntermediates(LogicNet a) {
    a = addInOut('a', a, width: 4);

    final intermediate1 = LogicNet(name: 'intermediate1', width: 4);
    final intermediate2 = LogicNet(name: 'intermediate2', width: 4);
    final intermediate3 = LogicNet(name: 'intermediate3', width: 4);
    final intermediate4 = LogicNet(name: 'intermediate4', width: 4);

    a <= intermediate1;
    intermediate1 <= intermediate2;
    intermediate1 <= intermediate3;
    intermediate3 <= intermediate1;
    intermediate4 <= intermediate2;

    addOutput('b', width: 4) <= intermediate4;
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
      in4normal,
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
  NetArrayTopMod(Logic x, NetArrayIntf intf) : super(name: 'netarrtop') {
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

class NetfulLogicStructure extends LogicStructure {
  NetfulLogicStructure()
      : super([
          LogicNet(name: 'structnet', width: 4),
          Logic(name: 'structlogic', width: 4)
        ]);
}

class NetsStructsArraysDriving extends Module {
  NetsStructsArraysDriving(
      LogicNet logicNetInOut, LogicArray logicArrayNetInOut)
      : assert(logicArrayNetInOut.isNet, 'expect a net'),
        super(name: 'nets_structs_arrays_driving') {
    logicNetInOut = addInOut('logicNetInOut', logicNetInOut, width: 8);
    logicArrayNetInOut = addInOutArray('logicArrayNetInOut', logicArrayNetInOut,
        dimensions: [4], elementWidth: 2);

    final struct = NetfulLogicStructure();
    struct <= logicNetInOut;
    final outStruct = addOutput('outStruct', width: 8);
    outStruct <= struct;

    logicArrayNetInOut <= struct;
  }
}

class AlwaysBlocksConnectionsNets extends Module {
  AlwaysBlocksConnectionsNets(
      LogicNet a, LogicNet b, LogicNet aOut, LogicNet bOut) {
    a = addInOut('a', a, width: 8);
    b = addInOut('b', b, width: 8);
    aOut = addInOut('aOut', aOut, width: 8);
    bOut = addInOut('bOut', bOut, width: 8);

    Combinational([aOut < a]);
    Sequential(SimpleClockGenerator(10).clk, [bOut < b]);
  }
}

//TODO: test gate operations on nets (like binary operations & |), keep an eye out for wire name inlineing? shouldnt happen if feeding into a wire port!
//TODO: test build when misconnected inout (without a port)
//TODO: test two inout ports of a module connected to the same signal! (this appears to have triggered another bug? how to tell if signal is internal?)

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

  test('logicnet glitch and changed', () async {
    final net = LogicNet(width: 8)..put(0);

    var i = 0;

    net.glitch.listen((args) {
      expect(net.value.toInt(), i + 1);
      i++;
    });

    net.changed.listen((event) {
      expect(event.previousValue.toInt(), i - 1);
      expect(event.newValue.toInt(), i);
    });

    for (var j = 0; j < 10; j++) {
      Simulator.registerAction(j * 10, () => net.put(j));
    }

    Simulator.setMaxSimTime(1000);
    await Simulator.run();
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

  test('multiple named intermediate nets', () async {
    final mod = MultipleNamedIntermediates(LogicNet(width: 4));

    await mod.build();

    final sv = mod.generateSynth();
    expect(sv, contains('intermediate1'));
    expect(sv, contains('intermediate2'));
    expect(sv, contains('intermediate3'));
    expect(sv, contains('intermediate4'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 1}, {'b': 1}),
      Vector({'a': 'z'}, {'b': 'z'}),
      Vector({'a': 'x'}, {'b': 'x'}),
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
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }
  });

  test('structures, arrays, and nets driving together', () async {
    final mod =
        NetsStructsArraysDriving(LogicNet(width: 8), LogicArray.net([4], 2));

    await mod.build();

    final vectors = [
      Vector({'logicNetInOut': 0xab},
          {'logicArrayNetInOut': 0xab, 'outStruct': 0xab}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
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
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('net arrays', () {
    test('simple build', () async {
      final mod = NetArrayTopMod(Logic(width: 8), NetArrayIntf());
      await mod.build();

      final sv = mod.generateSynth();
      expect(sv, contains('wire [1:0][1:0][7:0] bd3'));
    });

    test('connections and build', () async {
      final mod = NetArrayTopMod(Logic(width: 8), NetArrayIntf());
      await mod.build();

      final vectors = [
        Vector({'x': 0xaa}, {'ad2': 0xaa55, 'bd3': 0x55aa55aa})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  test('always blocks with nets', () async {
    final mod = AlwaysBlocksConnectionsNets(
      LogicNet(width: 8),
      LogicNet(width: 8),
      LogicNet(width: 8),
      LogicNet(width: 8),
    );
    await mod.build();

    final vectors = [
      Vector({'a': 0x11, 'b': 0xaa}, {'aOut': 0x11}),
      Vector({'a': 0x22, 'b': 0xbb}, {'aOut': 0x22, 'bOut': 0xaa}),
      Vector({'a': 0x33, 'b': 0xcc}, {'aOut': 0x33, 'bOut': 0xbb}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}

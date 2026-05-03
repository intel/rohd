// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// inout_loopback_test.dart
// Tests for inout port loopback scenarios where two inout ports of a
// submodule are connected externally to the same net by a parent module.
//
// 2026 April 17
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// A module with two inout ports that are NOT connected internally.
/// Each port just connects to an internal tristate buffer.
class InnerModWithTwoInouts extends Module {
  InnerModWithTwoInouts(
    Logic isDriverA,
    Logic toDriveA,
    LogicNet ioA,
    Logic isDriverB,
    Logic toDriveB,
    LogicNet ioB,
  ) : super(name: 'inner', definitionName: 'inner') {
    isDriverA = addInput('isDriverA', isDriverA);
    toDriveA = addInput('toDriveA', toDriveA, width: toDriveA.width);
    ioA = addInOut('ioA', ioA, width: toDriveA.width);

    isDriverB = addInput('isDriverB', isDriverB);
    toDriveB = addInput('toDriveB', toDriveB, width: toDriveB.width);
    ioB = addInOut('ioB', ioB, width: toDriveB.width);

    ioA <= TriStateBuffer(toDriveA, enable: isDriverA).out;
    ioB <= TriStateBuffer(toDriveB, enable: isDriverB).out;
  }
}

/// A top module that connects both inout ports of [InnerModWithTwoInouts]
/// to the SAME external net, creating a loopback.
class OuterLoopbackModule extends Module {
  Logic get observed => output('observed');

  OuterLoopbackModule(
    Logic isDriverA,
    Logic toDriveA,
    Logic isDriverB,
    Logic toDriveB,
  ) : super(name: 'outer', definitionName: 'outer') {
    isDriverA = addInput('isDriverA', isDriverA);
    toDriveA = addInput('toDriveA', toDriveA, width: toDriveA.width);
    isDriverB = addInput('isDriverB', isDriverB);
    toDriveB = addInput('toDriveB', toDriveB, width: toDriveB.width);

    // A single shared net that both inout ports connect to.
    final sharedNet = LogicNet(name: 'sharedNet', width: 8);

    // Both ioA and ioB of the inner module connect to the same net.
    InnerModWithTwoInouts(
      isDriverA,
      toDriveA,
      sharedNet,
      isDriverB,
      toDriveB,
      sharedNet,
    );

    addOutput('observed', width: 8) <= sharedNet;
  }
}

/// A simpler version: inner module has two inout ports, no logic, just ports.
class SimpleInnerTwoInouts extends Module {
  SimpleInnerTwoInouts(LogicNet ioA, LogicNet ioB)
      : super(name: 'simpleInner', definitionName: 'simpleInner') {
    addInOut('ioA', ioA, width: ioA.width);
    addInOut('ioB', ioB, width: ioB.width);
  }
}

/// Outer module that loopbacks both inout ports of [SimpleInnerTwoInouts]
/// to the same net.
class SimpleOuterLoopback extends Module {
  SimpleOuterLoopback(LogicNet externalNet)
      : super(name: 'simpleOuter', definitionName: 'simpleOuter') {
    externalNet =
        addInOut('externalNet', externalNet, width: externalNet.width);

    // Connect both inout ports to the same net via this module's port.
    SimpleInnerTwoInouts(externalNet, externalNet);
  }
}

/// Inner module where the two inout ports ARE connected internally via a net.
class InnerModInternallyConnected extends Module {
  InnerModInternallyConnected(
    Logic isDriverA,
    Logic toDriveA,
    LogicNet ioA,
    Logic isDriverB,
    Logic toDriveB,
    LogicNet ioB,
  ) : super(name: 'innerConnected', definitionName: 'innerConnected') {
    isDriverA = addInput('isDriverA', isDriverA);
    toDriveA = addInput('toDriveA', toDriveA, width: toDriveA.width);
    ioA = addInOut('ioA', ioA, width: toDriveA.width);

    isDriverB = addInput('isDriverB', isDriverB);
    toDriveB = addInput('toDriveB', toDriveB, width: toDriveB.width);
    ioB = addInOut('ioB', ioB, width: toDriveB.width);

    ioA <= TriStateBuffer(toDriveA, enable: isDriverA).out;
    ioB <= TriStateBuffer(toDriveB, enable: isDriverB).out;

    // Internally connect the two inout ports via a net.
    ioA <= ioB;
  }
}

/// Outer module using [InnerModInternallyConnected] with both inout ports
/// connected to the same external net. This creates a scenario where the
/// inner module already has a net_connect internally, and the outer module
/// also connects them to the same net.
class OuterWithInternallyConnectedInner extends Module {
  Logic get observed => output('observed');

  OuterWithInternallyConnectedInner(
    Logic isDriverA,
    Logic toDriveA,
    Logic isDriverB,
    Logic toDriveB,
  ) : super(name: 'outerConnected', definitionName: 'outerConnected') {
    isDriverA = addInput('isDriverA', isDriverA);
    toDriveA = addInput('toDriveA', toDriveA, width: toDriveA.width);
    isDriverB = addInput('isDriverB', isDriverB);
    toDriveB = addInput('toDriveB', toDriveB, width: toDriveB.width);

    final sharedNet = LogicNet(name: 'sharedNet', width: 8);

    InnerModInternallyConnected(
      isDriverA,
      toDriveA,
      sharedNet,
      isDriverB,
      toDriveB,
      sharedNet,
    );

    addOutput('observed', width: 8) <= sharedNet;
  }
}

/// Inner module with a clk input and two inout ports, no internal connection
/// between the inout ports.
class InnerWithClkAndTwoInouts extends Module {
  InnerWithClkAndTwoInouts(Logic clk, LogicNet ioA, LogicNet ioB)
      : super(name: 'innerClk', definitionName: 'innerClk') {
    clk = addInput('clk', clk);
    ioA = addInOut('ioA', ioA, width: ioA.width);
    ioB = addInOut('ioB', ioB, width: ioB.width);
  }
}

/// Outer module that passes clk down to inner, and loopbacks the inner's
/// two inout ports to the same net. The net is not connected to anything
/// else — no output, no other consumer.
class OuterClkLoopback extends Module {
  OuterClkLoopback(Logic clk)
      : super(name: 'outerClkLoopback', definitionName: 'outerClkLoopback') {
    clk = addInput('clk', clk);

    final ioA = LogicNet(name: 'ioA', width: 8, naming: Naming.mergeable);
    final ioB = LogicNet(name: 'ioB', width: 8, naming: Naming.mergeable);
    ioA <= ioB;

    InnerWithClkAndTwoInouts(clk, ioA, ioB);
  }
}

/// A pair interface loopback scenario: a module takes two PairInterfaces
/// where the inout ports end up connected to the same net.
class LoopbackPairInterface extends PairInterface {
  Logic get clk => port('clk');
  Logic get io => port('io');

  LoopbackPairInterface()
      : super(
          portsFromProvider: [Logic.port('req', 8)],
          portsFromConsumer: [Logic.port('rsp', 8)],
          sharedInputPorts: [Logic.port('clk')],
          commonInOutPorts: [LogicNet.port('io', 8)],
        );

  @override
  LoopbackPairInterface clone() => LoopbackPairInterface();
}

/// Provider sub-module: drives req, reads rsp, has inout io.
class LoopbackProvider extends Module {
  LoopbackProvider(LoopbackPairInterface intf) : super(name: 'provider') {
    intf = addPairInterfacePorts(intf, PairRole.provider);
  }
}

/// Consumer sub-module: reads req, drives rsp, has inout io.
class LoopbackConsumer extends Module {
  LoopbackConsumer(LoopbackPairInterface intf) : super(name: 'consumer') {
    intf = addPairInterfacePorts(intf, PairRole.consumer);
  }
}

/// Top module connecting provider and consumer to the same PairInterface,
/// sharing the same inout net.
class LoopbackPairTop extends Module {
  LoopbackPairTop(Logic clk) : super(name: 'loopbackPairTop') {
    clk = addInput('clk', clk);
    final intf = LoopbackPairInterface();
    intf.clk <= clk;
    LoopbackProvider(intf);
    LoopbackConsumer(intf);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('inout loopback', () {
    test('two inout ports of submodule connected to same net externally',
        () async {
      final mod = OuterLoopbackModule(
        Logic(),
        Logic(width: 8),
        Logic(),
        Logic(width: 8),
      );
      await mod.build();

      final sv = mod.generateSynth();

      // The outer module should NOT contain an internal net_connect
      // for the loopback — the submodule ports should just be wired to the
      // same signal in the instantiation, no net_connect needed in outer.
      final outerModuleSv = _extractModuleSv(sv, 'outer');
      expect(outerModuleSv, isNot(contains('net_connect')),
          reason: 'Outer module should not have net_connect '
              'when two inout ports are externally connected to same net');

      // Functional check: when A drives, observed should see A's value.
      final vectors = [
        Vector(
          {'isDriverA': 1, 'toDriveA': 0xaa, 'isDriverB': 0, 'toDriveB': 0},
          {'observed': 0xaa},
        ),
        // When B drives, observed should see B's value.
        Vector(
          {'isDriverA': 0, 'toDriveA': 0, 'isDriverB': 1, 'toDriveB': 0x55},
          {'observed': 0x55},
        ),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('simple two inout ports loopback SV generation', () async {
      final mod = SimpleOuterLoopback(LogicNet(width: 8));
      await mod.build();

      final sv = mod.generateSynth();

      final outerModuleSv = _extractModuleSv(sv, 'simpleOuter');
      expect(outerModuleSv, isNot(contains('net_connect')),
          reason: 'Simple outer module should not have net_connect '
              'when both inout ports map to the same external net');

      // The inner module should instantiate with both ioA and ioB mapped
      // to the same signal (externalNet). No net_connect should be needed.
      expect(outerModuleSv, contains('simpleInner'));
    });

    test('pair interface provider and consumer share inout net', () async {
      final mod = LoopbackPairTop(Logic());
      await mod.build();

      final sv = mod.generateSynth();

      // Check for net_connect in the top module
      final topModuleSv = _extractModuleSv(sv, 'LoopbackPairTop');
      expect(topModuleSv, isNot(contains('net_connect')),
          reason: 'PairInterface top module should not have net_connect '
              'when provider and consumer share the same inout net');

      // The provider and consumer should be instantiated with the same
      // inout signal without needing net_connect in the top.
      expect(topModuleSv, contains('LoopbackProvider'));
      expect(topModuleSv, contains('LoopbackConsumer'));
    });

    test(
        'inner module with internal net between inout ports, '
        'external loopback to same net', () async {
      final mod = OuterWithInternallyConnectedInner(
        Logic(),
        Logic(width: 8),
        Logic(),
        Logic(width: 8),
      );
      await mod.build();

      final sv = mod.generateSynth();

      // The inner module SHOULD have a net_connect (connecting ioA <= ioB).
      final innerModuleSv = _extractModuleSv(sv, 'innerConnected');
      expect(innerModuleSv, contains('net_connect'),
          reason: 'Inner module should have net_connect for ioA <= ioB');

      // The outer module should NOT have an extra net_connect —
      // it should just wire both ports to sharedNet in the instantiation.
      final outerModuleSv = _extractModuleSv(sv, 'outerConnected');
      expect(outerModuleSv, isNot(contains('net_connect')),
          reason: 'Outer module should not have net_connect '
              'when two inout ports of inner are externally looped');

      // Functional: when A drives, observed sees A's value.
      // When B drives, observed sees B's value.
      // Both go through the shared net, and the internal ioA<=ioB
      // connection means both ports see the driven value.
      final vectors = [
        Vector(
          {'isDriverA': 1, 'toDriveA': 0xaa, 'isDriverB': 0, 'toDriveB': 0},
          {'observed': 0xaa},
        ),
        Vector(
          {'isDriverA': 0, 'toDriveA': 0, 'isDriverB': 1, 'toDriveB': 0x55},
          {'observed': 0x55},
        ),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('inout loopback with only clk passed through, net not used elsewhere',
        () async {
      final mod = OuterClkLoopback(Logic());
      await mod.build();

      final sv = mod.generateSynth();

      // The outer module should NOT have a net_connect — the loopback net
      // is only used as port connections in the inner instantiation.
      final outerModuleSv = _extractModuleSv(sv, 'outerClkLoopback');
      expect(outerModuleSv, isNot(contains('net_connect')),
          reason: 'Outer module should not have net_connect when the '
              'loopback net is only connected to two inout ports of inner');

      // The inner module should be instantiated with both ioA and ioB
      // mapped to the same loopbackNet signal.
      expect(outerModuleSv, contains('innerClk'));
      expect(outerModuleSv, contains('.clk(clk)'));

      // make sure there are actually connections in those pins (not empty)
      expect(outerModuleSv, isNot(contains('.ioA()')));
      expect(outerModuleSv, isNot(contains('.ioB()')));
      expect(outerModuleSv,
          contains(RegExp(r'^\s*wire \[7:0\] io[AB];\s*$', multiLine: true)));

      // Should compile cleanly in iverilog (build-only, no vectors needed
      // since there are no outputs to check).
      SimCompare.checkIverilogVector(mod, [], buildOnly: true);
    });
  });
}

/// Extracts the SV text for a specific module definition from the full
/// generated SV string.
String _extractModuleSv(String fullSv, String moduleName) {
  final modulePattern = RegExp(
    'module $moduleName\\b.*?endmodule',
    dotAll: true,
  );
  final match = modulePattern.firstMatch(fullSv);
  return match?.group(0) ?? '';
}

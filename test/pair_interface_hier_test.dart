// Copyright (C) 2023-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// pair_interface_hier_test.dart
// Tests for PairInterface with hierarchy
//
// 2023 March 9
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SubInterface extends PairInterface {
  Logic get req => port('req');
  Logic get rsp => port('rsp');
  Logic get io => port('io');
  LogicArray get ioArr => port('io_arr') as LogicArray;

  SubInterface({super.modify})
      : super(
          portsFromConsumer: [Logic.port('rsp')],
          portsFromProvider: [LogicArray.port('req')],
          commonInOutPorts: [
            LogicNet.port('io'),
            LogicArray.netPort('io_arr', [3])
          ],
        );

  @override
  SubInterface clone() => SubInterface(modify: modify);
}

class TopLevelInterface extends PairInterface {
  Logic get clk => port('clk');

  final int numSubInterfaces;

  final List<SubInterface> subIntfs = [];

  TopLevelInterface(this.numSubInterfaces)
      : super(
          sharedInputPorts: [Logic.port('clk')],
        ) {
    for (var i = 0; i < numSubInterfaces; i++) {
      subIntfs.add(addSubInterface(
          'sub$i',
          SubInterface(
            modify: (original) => '${original}_$i',
          )));
    }
  }

  @override
  TopLevelInterface clone() => TopLevelInterface(numSubInterfaces);
}

class HierProducer extends Module {
  late final TopLevelInterface _intf;
  HierProducer(TopLevelInterface intf) {
    _intf = intf.clone()..pairConnectIO(this, intf, PairRole.provider);

    _intf.subIntfs[0].req <= FlipFlop(_intf.clk, _intf.subIntfs[0].rsp).q;
  }
}

class HierConsumer extends Module {
  late final TopLevelInterface _intf;
  HierConsumer(TopLevelInterface intf) {
    _intf = intf.clone()..pairConnectIO(this, intf, PairRole.consumer);

    _intf.subIntfs[1].rsp <= FlipFlop(_intf.clk, _intf.subIntfs[1].req).q;
  }
}

class HierTop extends Module {
  HierTop(Logic clk) {
    clk = addInput('clk', clk);
    final intf = TopLevelInterface(3);
    intf.clk <= clk;
    HierConsumer(intf);
    HierProducer(intf);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('hier pair interface', () async {
    final mod = HierTop(Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('HierConsumer  unnamed_module'));
    expect(sv, contains('HierProducer  unnamed_module'));
    expect(sv, contains('inout wire io_0'));
    expect(sv, contains('inout wire [2:0] io_arr_0'));
  });
}

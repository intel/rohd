// Copyright (C) 2023 Intel Corporation
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
  Logic get rsp => port('rsp');
  Logic get req => port('req');

  SubInterface({super.modify})
      : super(
          portsFromConsumer: [Port('rsp')],
          portsFromProvider: [Port('req')],
        );
  SubInterface.clone(SubInterface super.otherInterface) : super.clone();
}

class TopLevelInterface extends PairInterface {
  Logic get clk => port('clk');

  final int numSubInterfaces;

  final List<SubInterface> subIntfs = [];

  TopLevelInterface(this.numSubInterfaces)
      : super(
          sharedInputPorts: [Port('clk')],
        ) {
    for (var i = 0; i < numSubInterfaces; i++) {
      subIntfs.add(addSubInterface(
          'sub$i',
          SubInterface(
            modify: (original) => '${original}_$i',
          )));
    }
  }

  TopLevelInterface.clone(TopLevelInterface otherInterface)
      : this(otherInterface.numSubInterfaces);
}

class HierProducer extends Module {
  late final TopLevelInterface _intf;
  HierProducer(TopLevelInterface intf) {
    _intf = TopLevelInterface.clone(intf)
      ..simpleConnectIO(this, intf, PairRole.provider);

    _intf.subIntfs[0].req <= FlipFlop(_intf.clk, _intf.subIntfs[0].rsp).q;
  }
}

class HierConsumer extends Module {
  late final TopLevelInterface _intf;
  HierConsumer(TopLevelInterface intf) {
    _intf = TopLevelInterface.clone(intf)
      ..simpleConnectIO(this, intf, PairRole.consumer);

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
  test('hier pair interface', () async {
    final mod = HierTop(Logic());
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv, contains('HierConsumer  unnamed_module'));
    expect(sv, contains('HierProducer  unnamed_module'));
  });
}

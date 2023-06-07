// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// pair_interface_test.dart
// Tests for PairInterface
//
// 2023 March 9
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SimpleInterface extends PairInterface {
  Logic get clk => port('clk');
  Logic get req => port('req');
  Logic get rsp => port('rsp');

  SimpleInterface()
      : super(
          portsFromConsumer: [Port('rsp')],
          portsFromProvider: [Port('req')],
          sharedInputPorts: [Port('clk')],
          modify: (original) => 'simple_$original',
        );

  SimpleInterface.clone(SimpleInterface super.otherInterface) : super.clone();
}

class SimpleProvider extends Module {
  late final SimpleInterface _intf;
  SimpleProvider(SimpleInterface intf) {
    _intf = SimpleInterface.clone(intf)
      ..simpleConnectIO(this, intf, PairRole.provider);

    SimpleSubProvider(_intf);
  }
}

class SimpleSubProvider extends Module {
  SimpleSubProvider(SimpleInterface intf) {
    SimpleInterface.clone(intf).simpleConnectIO(this, intf, PairRole.provider);
  }
}

class SimpleConsumer extends Module {
  SimpleConsumer(SimpleInterface intf) {
    SimpleInterface.clone(intf).simpleConnectIO(this, intf, PairRole.consumer);
  }
}

class SimpleTop extends Module {
  SimpleTop(Logic clk) {
    clk = addInput('clk', clk);
    final intf = SimpleInterface();
    intf.clk <= clk;
    SimpleConsumer(intf);
    SimpleProvider(intf);
  }
}

void main() {
  test('simple pair interface', () async {
    final mod = SimpleTop(Logic());
    await mod.build();

    // Make sure the "modify" went through:
    final sv = mod.generateSynth();
    expect(sv, contains('input logic simple_clk'));
  });
}

/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// pair_interface_test.dart
/// Tests for PairInterface
///
/// 2023 March 9
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SimpleInterface extends PairInterface {
  Logic get clk => port('clk');
  SimpleInterface()
      : super(
          portsFromConsumer: [Port('rsp')],
          portsFromProducer: [Port('req')],
          sharedInputPorts: [Port('clk')],
        );
  SimpleInterface.match(SimpleInterface super.otherInterface) : super.match();
}

class SimpleProducer extends Module {
  late final SimpleInterface _intf;
  SimpleProducer(SimpleInterface intf) {
    _intf = SimpleInterface.match(intf)
      ..simpleConnect(this, intf, PairRole.producer);
  }
}

class SimpleConsumer extends Module {
  late final SimpleInterface _intf;
  SimpleConsumer(SimpleInterface intf) {
    _intf = SimpleInterface.match(intf)
      ..simpleConnect(this, intf, PairRole.consumer);
  }
}

class SimpleTop extends Module {
  SimpleTop(Logic clk) {
    clk = addInput('clk', clk);
    final intf = SimpleInterface();
    intf.clk <= clk;
    SimpleConsumer(intf);
    SimpleProducer(intf);
  }
}

void main() {
  test('simple pair interface', () async {
    final mod = SimpleTop(Logic());
    await mod.build();
    print(mod.generateSynth());
  });
}

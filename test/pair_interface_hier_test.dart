/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// pair_interface_hier_test.dart
/// Tests for PairInterface with hierarchy
///
/// 2023 March 9
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SubInterface extends PairInterface {
  SubInterface()
      : super(
          portsFromConsumer: [Port('rsp')],
          portsFromProducer: [Port('req')],
        );
  SubInterface.match(SubInterface super.otherInterface) : super.clone();
}

class TopLevelInterface extends PairInterface {
  Logic get clk => port('clk');

  final int numSubInterfaces;

  final List<SubInterface> subInterfaces = [];
  TopLevelInterface(this.numSubInterfaces)
      : super(
          sharedInputPorts: [Port('clk')],
        ) {
    for (var i = 0; i < numSubInterfaces; i++) {
      final subInterface = SubInterface();
      subInterfaces.add(subInterface);
    }
  }

  TopLevelInterface.match(TopLevelInterface otherInterface)
      : this(otherInterface.numSubInterfaces);

  @override
  void connectIO(Module module, Interface<dynamic> srcInterface,
      {Iterable<PairDirection>? inputTags,
      Iterable<PairDirection>? outputTags,
      String Function(String original)? uniquify}) {
    super.connectIO(module, srcInterface,
        inputTags: inputTags, outputTags: outputTags, uniquify: uniquify);

    srcInterface as TopLevelInterface;

    final role = outputTags!.contains(PairDirection.fromProvider)
        ? PairRole.provider
        : PairRole.consumer;

    for (var i = 0; i < numSubInterfaces; i++) {
      subInterfaces[i].simpleConnectIO(
          module, srcInterface.subInterfaces[i], role,
          uniquify: (original) => '${original}_$i');
    }
  }
}

class HierProducer extends Module {
  late final TopLevelInterface _intf;
  HierProducer(TopLevelInterface intf) {
    _intf = TopLevelInterface.match(intf)
      ..simpleConnectIO(this, intf, PairRole.provider);
  }
}

class HierConsumer extends Module {
  late final TopLevelInterface _intf;
  HierConsumer(TopLevelInterface intf) {
    _intf = TopLevelInterface.match(intf)
      ..simpleConnectIO(this, intf, PairRole.consumer);
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
    print(mod.generateSynth());
  });
}

// Copyright (C) 2023-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// pair_interface_test.dart
// Tests for PairInterface
//
// 2023 March 9
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SimpleInterface extends PairInterface {
  Logic get clk => port('clk');
  Logic get req => port('req');
  Logic get rsp => port('rsp');
  Logic get io => port('io');
  LogicArray get ioArr => port('io_arr') as LogicArray;

  SimpleInterface()
      : super(
          portsFromConsumer: [Logic.port('rsp')],
          portsFromProvider: [LogicArray.port('req')],
          sharedInputPorts: [Logic.port('clk')],
          commonInOutPorts: [
            LogicNet.port('io'),
            LogicArray.netPort('io_arr', [3])
          ],
          modify: (original) => 'simple_$original',
        );

  @override
  SimpleInterface clone() => SimpleInterface();
}

class SimpleProvider extends Module {
  late final SimpleInterface _intf;
  SimpleProvider(SimpleInterface intf) {
    _intf = addPairInterfacePorts(intf, PairRole.provider);

    SimpleSubProvider(_intf);
  }
}

class SimpleSubProvider extends Module {
  SimpleSubProvider(SimpleInterface intf) {
    addPairInterfacePorts(intf, PairRole.provider);
  }
}

class SimpleConsumer extends Module {
  SimpleConsumer(SimpleInterface intf) {
    addPairInterfacePorts(intf, PairRole.consumer);
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

class PassthroughPairIntfModule extends Module {
  PassthroughPairIntfModule(SimpleInterface intf1, SimpleInterface intf2,
      {required bool useConditional, required bool useConnectApi}) {
    intf1 = useConnectApi
        ? addPairInterfacePorts(
            intf1,
            PairRole.consumer,
            uniquify: (original) => '${original}_1',
          )
        : (intf1.clone()
          ..pairConnectIO(
            this,
            intf1,
            PairRole.consumer,
            uniquify: (original) => '${original}_1',
          ));
    intf2 = useConnectApi
        ? addInterfacePorts(
            intf2,
            inputTags: {PairDirection.fromConsumer},
            outputTags: {PairDirection.fromProvider},
            inOutTags: {PairDirection.commonInOuts},
            uniquify: (original) => '${original}_2',
          )
        : (intf2.clone()
          ..connectIO(
            this,
            intf2,
            inputTags: {PairDirection.fromConsumer},
            outputTags: {PairDirection.fromProvider},
            inOutTags: {PairDirection.commonInOuts},
            uniquify: (original) => '${original}_2',
          ));

    if (useConditional) {
      Combinational([
        intf1.conditionalDriveOther(intf2, {PairDirection.fromProvider}),
        intf1.conditionalReceiveOther(intf2, {PairDirection.fromConsumer}),
      ]);
    } else {
      intf1
        ..driveOther(intf2, {PairDirection.fromProvider})
        ..receiveOther(intf2, {PairDirection.fromConsumer});
    }

    intf1.io <= intf2.io;
    intf1.ioArr <= intf2.ioArr;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple pair interface', () async {
    final mod = SimpleTop(Logic());
    await mod.build();

    // Make sure the "modify" went through:
    final sv = mod.generateSynth();
    expect(sv, contains('input logic simple_clk'));
  });

  group('drive and receive other', () {
    Future<void> testDriveAndReceive(
        {required bool useConditional, required bool useConnectApi}) async {
      final mod = PassthroughPairIntfModule(
        SimpleInterface(),
        SimpleInterface(),
        useConditional: useConditional,
        useConnectApi: useConnectApi,
      );
      await mod.build();

      final vectors = [
        Vector({
          'simple_req_1': 1,
          'simple_rsp_2': 1,
          'simple_io_1': 1,
          'simple_io_arr_2': 2
        }, {
          'simple_req_2': 1,
          'simple_rsp_1': 1,
          'simple_io_2': 1,
          'simple_io_arr_1': 2
        }),
        Vector({
          'simple_req_1': 0,
          'simple_rsp_2': 1,
          'simple_io_1': 0,
          'simple_io_arr_2': 5
        }, {
          'simple_req_2': 0,
          'simple_rsp_1': 1,
          'simple_io_2': 0,
          'simple_io_arr_1': 5
        }),
        Vector({'simple_req_1': 1, 'simple_rsp_2': 0},
            {'simple_req_2': 1, 'simple_rsp_1': 0}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    }

    for (final useConditional in [false, true]) {
      for (final useConnectApi in [false, true]) {
        test(
            'with useConnectApi: $useConnectApi, '
            'with useConditional: $useConditional', () async {
          await testDriveAndReceive(
            useConditional: useConditional,
            useConnectApi: useConnectApi,
          );
        });
      }
    }
  });
}

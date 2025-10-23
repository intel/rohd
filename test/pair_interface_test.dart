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

          // keep this around to test deprecated functionality
          // ignore: deprecated_member_use_from_same_package
          modify: (original) => 'simple_$original',
        );

  @override
  SimpleInterface clone() => SimpleInterface();
}

class SubInterface extends PairInterface {
  Logic get subReq => port('sub_req');
  Logic get subRsp => port('sub_rsp');

  SubInterface()
      : super(
          portsFromConsumer: [Logic.port('sub_rsp', 8)],
          portsFromProvider: [Logic.port('sub_req', 8)],
        );

  @override
  SubInterface clone() => SubInterface();
}

class HierarchicalInterface extends PairInterface {
  Logic get mainReq => port('main_req');
  Logic get mainRsp => port('main_rsp');
  SubInterface get sub1 => subInterfaces['sub1']! as SubInterface;
  SubInterface get sub2 => subInterfaces['sub2']! as SubInterface;

  HierarchicalInterface()
      : super(
          portsFromProvider: [Logic.port('main_req', 8)],
          portsFromConsumer: [Logic.port('main_rsp', 8)],
        ) {
    addSubInterface('sub1', SubInterface(), uniquify: (orig) => 'sub1_$orig');
    addSubInterface('sub2', SubInterface(),
        uniquify: (orig) => 'sub2_$orig', reverse: true);
  }

  @override
  HierarchicalInterface clone() => HierarchicalInterface();
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

class SubInterfaceTestModule extends Module {
  SubInterfaceTestModule(
      HierarchicalInterface intf1, HierarchicalInterface intf2,
      {required bool useConditional}) {
    intf1 = addPairInterfacePorts(
      intf1,
      PairRole.consumer,
      uniquify: (original) => 'intf1_$original',
    );
    intf2 = addPairInterfacePorts(
      intf2,
      PairRole.provider,
      uniquify: (original) => 'intf2_$original',
    );

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

  group('sub-interface drive and receive other', () {
    for (final useConditional in [false, true]) {
      test('with useConditional: $useConditional', () async {
        final mod = SubInterfaceTestModule(
          HierarchicalInterface(),
          HierarchicalInterface(),
          useConditional: useConditional,
        );
        await mod.build();

        final vectors = [
          Vector({'intf1_main_req': 0x01, 'intf2_main_rsp': 0x23},
              {'intf2_main_req': 0x01, 'intf1_main_rsp': 0x23}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }
  });

  test('hierarchical interface creation and access', () {
    final intf = HierarchicalInterface();

    // Test that sub-interfaces were created properly
    expect(intf.subInterfaces.containsKey('sub1'), isTrue);
    expect(intf.subInterfaces.containsKey('sub2'), isTrue);
    expect(intf.subInterfaces.length, equals(2));

    // Test access to sub-interface ports
    expect(intf.sub1.subReq.width, equals(1));
    expect(intf.sub1.subRsp.width, equals(1));
    expect(intf.sub2.subReq.width, equals(1));
    expect(intf.sub2.subRsp.width, equals(1));
  });

  test('sub-interface error handling', () {
    final intf1 = HierarchicalInterface();
    final intf2 = SimpleInterface(); // Doesn't have sub-interfaces

    // Should throw when trying to drive a non-PairInterface with sub-interfaces
    expect(
      () => intf1.driveOther(intf2, {PairDirection.fromProvider}),
      returnsNormally, // Base interface operations should still work
    );

    // Create another hierarchical interface missing a sub-interface
    final intf3 = PairInterface();
    expect(
      () => intf1.driveOther(intf3, {PairDirection.fromProvider}),
      throwsA(isA<InterfaceTypeException>()),
    );
  });
}

// Copyright (C) 2023-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// provider_consumer_test.dart
// Tests for PairInterface with an example of provider and consumer
//
// 2023 March 9
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// Creates a uniquification which adds a [prefix].
String Function(String) withPrefix(String prefix) =>
    (original) => '${prefix}_$original';

/// Creates a uniquification which adds a [suffix].
String Function(String) withSuffix(String suffix) =>
    (original) => '${original}_$suffix';

class DataInterface extends PairInterface {
  Logic get data => port('data');
  Logic get valid => port('valid');
  Logic get ready => port('ready');

  DataInterface()
      : super(
            portsFromProvider: [Logic.port('data', 32), Logic.port('valid')],
            portsFromConsumer: [Logic.port('ready')]);
  @override
  DataInterface clone() => DataInterface();
}

class RequestInterface extends PairInterface {
  final List<DataInterface> writeDatas = [];
  final int numWd;
  RequestInterface({this.numWd = 2}) {
    for (var wd = 0; wd < numWd; wd++) {
      writeDatas.add(addSubInterface(
        'write_data$wd',
        DataInterface(),
        uniquify: withPrefix('wd$wd'),
      ));
    }
  }

  @override
  RequestInterface clone() => RequestInterface(numWd: numWd);
}

class ResponseInterface extends PairInterface {
  late final DataInterface readData;
  ResponseInterface() : super() {
    readData = addSubInterface(
      'read_data',
      DataInterface(),
      reverse: true,
      uniquify: withPrefix('rd'),
    );
  }
  @override
  ResponseInterface clone() => ResponseInterface();
}

class PCInterface extends PairInterface {
  late final RequestInterface req;
  late final ResponseInterface rsp;
  PCInterface() {
    req = addSubInterface(
      'req',
      RequestInterface(),
      uniquify: withSuffix('req'),
    );
    rsp = addSubInterface(
      'rsp',
      ResponseInterface(),
      uniquify: withSuffix('rsp'),
    );
  }
  @override
  PCInterface clone() => PCInterface();
}

class Provider extends Module {
  Provider(Logic clk, Logic reset, RequestInterface reqIntf,
      ResponseInterface rspIntf) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    reqIntf = reqIntf.clone()
      ..pairConnectIO(
        this,
        reqIntf,
        PairRole.provider,
        uniquify: withSuffix('req'),
      );
    rspIntf = rspIntf.clone()
      ..pairConnectIO(
        this,
        rspIntf,
        PairRole.provider,
        uniquify: withSuffix('rsp'),
      );

    reqIntf.writeDatas[0].valid <= Const(1);
    reqIntf.writeDatas[1].valid <= Const(1);

    Sequential(clk, reset: reset, [
      reqIntf.writeDatas[0].data.incr(val: 2),
      reqIntf.writeDatas[1].data.incr(),
    ]);
  }
}

class Consumer extends Module {
  Consumer(Logic clk, Logic reset, RequestInterface reqIntf,
      ResponseInterface rspIntf) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    reqIntf = reqIntf.clone()
      ..pairConnectIO(
        this,
        reqIntf,
        PairRole.consumer,
        uniquify: withSuffix('req'),
      );
    rspIntf = rspIntf.clone()
      ..pairConnectIO(
        this,
        rspIntf,
        PairRole.consumer,
        uniquify: withSuffix('rsp'),
      );

    rspIntf.readData.valid <= Const(1);

    Sequential(clk, reset: reset, [
      rspIntf.readData.data <
          reqIntf.writeDatas.map((e) => e.data).reduce((a, b) => a + b),
      reqIntf.writeDatas[0].ready < 1,
      reqIntf.writeDatas[1].ready < 1,
    ]);
  }
}

class PCTop extends Module {
  PCTop(Logic reset) {
    final clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);

    final pcIntf = PCInterface();

    Provider(clk, reset, pcIntf.req, pcIntf.rsp);
    Consumer(clk, reset, pcIntf.req, pcIntf.rsp);

    addOutput('rsp_data', width: 32) <= pcIntf.rsp.readData.data;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('provider and consumer', () async {
    final mod = PCTop(Logic());
    await mod.build();

    final vectors = [
      Vector({'reset': 1}, {}),
      Vector({}, {}),
      Vector({'reset': 0}, {}),
      Vector({}, {}),
      Vector({}, {'rsp_data': 3}),
      Vector({}, {'rsp_data': 6}),
      Vector({}, {'rsp_data': 9}),
    ];

    final sv = mod.generateSynth();

    expect(sv, contains('''
module Provider (
input logic clk,
input logic reset,
input logic wd0_ready_req,
input logic wd1_ready_req,
input logic [31:0] rd_data_rsp,
input logic rd_valid_rsp,
output logic [31:0] wd0_data_req,
output logic wd0_valid_req,
output logic [31:0] wd1_data_req,
output logic wd1_valid_req,
output logic rd_ready_rsp
);
'''));

    expect(sv, contains('''
module Consumer (
input logic clk,
input logic reset,
input logic [31:0] wd0_data_req,
input logic wd0_valid_req,
input logic [31:0] wd1_data_req,
input logic wd1_valid_req,
input logic rd_ready_rsp,
output logic wd0_ready_req,
output logic wd1_ready_req,
output logic [31:0] rd_data_rsp,
output logic rd_valid_rsp
);
'''));

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}

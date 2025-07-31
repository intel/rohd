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

class DataInterface extends PairInterface {
  Logic get data => port('data');
  Logic get valid => port('valid');
  Logic get ready => port('ready');

  final String? prefix;

  DataInterface({this.prefix})
      : super(
            portsFromProvider: [Logic.port('data', 32), Logic.port('valid')],
            portsFromConsumer: [Logic.port('ready')],
            modify: (original) => [
                  if (prefix != null) prefix,
                  original,
                ].join('_'));
  @override
  DataInterface clone() => DataInterface(prefix: prefix);
}

class RequestInterface extends PairInterface {
  final List<DataInterface> writeDatas = [];
  final String name;
  final int numWd;
  RequestInterface({this.numWd = 2, this.name = 'req'})
      : super(modify: (original) => '${original}_$name') {
    for (var wd = 0; wd < numWd; wd++) {
      writeDatas.add(
          addSubInterface('write_data$wd', DataInterface(prefix: 'wd$wd')));
    }
  }

  RequestInterface.clone(RequestInterface other)
      : this(numWd: other.numWd, name: other.name);
  @override
  RequestInterface clone() => RequestInterface(numWd: numWd, name: name);
}

class ResponseInterface extends PairInterface {
  late final DataInterface readData;
  ResponseInterface() : super(modify: (original) => '${original}_rsp') {
    readData = addSubInterface('read_data', DataInterface(prefix: 'rd'),
        reverse: true);
  }
  @override
  ResponseInterface clone() => ResponseInterface();
}

class PCInterface extends PairInterface {
  late final RequestInterface req;
  late final ResponseInterface rsp;
  PCInterface() {
    req = addSubInterface('req', RequestInterface());
    rsp = addSubInterface('rsp', ResponseInterface());
  }
  @override
  PCInterface clone() => PCInterface();
}

class Provider extends Module {
  Provider(Logic clk, Logic reset, RequestInterface reqIntf,
      ResponseInterface rspIntf) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    reqIntf = RequestInterface.clone(reqIntf)
      ..pairConnectIO(this, reqIntf, PairRole.provider);
    rspIntf = ResponseInterface()
      ..pairConnectIO(this, rspIntf, PairRole.provider);

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
    reqIntf = RequestInterface.clone(reqIntf)
      ..pairConnectIO(this, reqIntf, PairRole.consumer);
    rspIntf = ResponseInterface()
      ..pairConnectIO(this, rspIntf, PairRole.consumer);

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

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}

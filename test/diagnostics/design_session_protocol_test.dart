// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_session_protocol_test.dart
// Tests for the typed ROHD design-session protocol.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _ProtocolLeaf extends Module {
  _ProtocolLeaf(Logic dataIn)
      : super(name: 'leaf', definitionName: 'ProtocolLeaf') {
    dataIn = addInput('dataIn', dataIn);
    addOutput('dataOut') <= ~dataIn;
  }
}

class _ProtocolTop extends Module {
  _ProtocolTop(Logic dataIn)
      : super(name: 'top', definitionName: 'ProtocolTop') {
    dataIn = addInput('dataIn', dataIn);
    final leaf = _ProtocolLeaf(dataIn);
    addOutput('dataOut') <= leaf.output('dataOut');
  }
}

void main() {
  tearDown(ModuleServices.instance.reset);

  test('round-trips occurrence addresses through session RPC calls', () async {
    final dut = _ProtocolTop(Logic(name: 'dataIn'));
    await dut.build();
    final handler = RohdDesignSessionProtocolHandler(
      InProcessRohdDesignSession(NetlistService(dut)),
    );

    final status = await handler.call(RohdDesignSessionProtocol.status, {});
    final signal = await handler.call(RohdDesignSessionProtocol.findSignal, {
      'path': 'top/dataOut',
    });
    final signalResult = Map<String, Object?>.from(signal['result']! as Map);
    final fanin = await handler.call(RohdDesignSessionProtocol.fanin, {
      'signal': signalResult,
    });

    expect(status, {
      'schemaVersion': 1,
      'ok': true,
      'result': {
        'epoch': 0,
        'ready': true,
        'designName': 'ProtocolTop',
        'capabilities': ['connectivity', 'hierarchy', 'waveform'],
      },
    });
    expect(signalResult['address'], isNotEmpty);
    expect(signalResult, {'address': isNotEmpty, 'kind': 'port'});
    expect(fanin['ok'], isTrue);
    expect(
      Map<String, Object?>.from(fanin['result']! as Map)['items']! as List,
      isNotEmpty,
    );

    final name = await handler.call(RohdDesignSessionProtocol.name, {
      'occurrence': signalResult,
    });
    expect(name['result'], {
      'address': signalResult['address'],
      'kind': 'port',
      'path': 'top/dataOut',
      'name': 'dataOut',
      'width': 1,
      'direction': 'output',
    });
  });

  test('reports malformed handle DTOs without invoking the session', () async {
    final dut = _ProtocolTop(Logic(name: 'dataIn'));
    await dut.build();
    final handler = RohdDesignSessionProtocolHandler(
      InProcessRohdDesignSession(NetlistService(dut)),
    );

    final result = await handler.call(RohdDesignSessionProtocol.fanout, {
      'signal': {'address': 'not.an.address'},
    });

    expect(result['ok'], isFalse);
    expect(result['schemaVersion'], 1);
    expect(
      Map<String, Object?>.from(result['error']! as Map)['code'],
      'invalidArgument',
    );
  });
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// dtd_discovery_test.dart
// Tests for DTD-backed VM service discovery.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_connection_host.dart';

class _DtdDiscoveryStub {
  _DtdDiscoveryStub._(this._server);

  final HttpServer _server;
  final requestedMethods = <String>[];
  final connections = <WebSocket>[];

  static Future<_DtdDiscoveryStub> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = _DtdDiscoveryStub._(server);
    unawaited(stub._listen());
    return stub;
  }

  Uri get uri => Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: _server.port,
      );

  Future<void> _listen() async {
    await for (final request in _server) {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        continue;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      connections.add(socket);
      socket.listen((message) {
        final request = jsonDecode(message as String) as Map<String, dynamic>;
        final method = request['method'] as String;
        requestedMethods.add(method);
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            'result': _resultFor(method),
          }),
        );
      });
    }
  }

  Map<String, Object> _resultFor(String method) => switch (method) {
        'getRegisteredServices' => {
            'type': 'RegisteredServicesResponse',
            'dtdServices': <String>['ConnectedApp'],
            'clientServices': <Map<String, Object>>[
              {
                'name': 'rohd',
                'methods': <Map<String, Object>>[],
              },
            ],
          },
        'ConnectedApp.getVmServices' => {
            'type': 'VmServicesResponse',
            'vmServices': [
              {
                'name': 'waveform demo',
                'uri': 'ws://internal:8181/app=/ws',
                'exposedUri': 'ws://forwarded:8181/app=/ws',
              },
            ],
          },
        _ => throw StateError('Unexpected DTD request: $method'),
      };

  Future<void> close() async {
    await Future.wait(connections.map((connection) => connection.close()));
    await _server.close(force: true);
  }
}

void main() {
  test('discovers VM services through the DTD JSON-RPC protocol', () async {
    final dtd = await _DtdDiscoveryStub.start();
    addTearDown(dtd.close);
    Set<String>? registeredServices;

    final services = await discoverVmServicesViaDtd(
      dtd.uri.toString(),
      onRegisteredServices: (services) => registeredServices = services,
    );

    expect(dtd.requestedMethods, [
      'getRegisteredServices',
      'ConnectedApp.getVmServices',
    ]);
    expect(registeredServices, {'rohd'});
    expect(services, hasLength(1));
    expect(services.single.name, 'waveform demo');
    expect(services.single.uri, 'ws://internal:8181/app=/ws');
    expect(services.single.exposedUri, 'ws://forwarded:8181/app=/ws');
    expect(services.single.connectionUri, 'ws://forwarded:8181/app=/ws');
  });
}

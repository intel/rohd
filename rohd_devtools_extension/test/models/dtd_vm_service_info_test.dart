// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// dtd_vm_service_info_test.dart
// Tests for DTD VM service display and connection information.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/dtd_vm_service_info.dart';

void main() {
  group('DtdVmServiceInfo', () {
    test('uses the exposed URI for connection and display when available', () {
      final service = DtdVmServiceInfo.fromFields(
        uri: 'ws://localhost:8181',
        exposedUri: 'ws://forwarded-host:8181',
        name: 'counter demo',
        autoReconnect: true,
      );

      expect(service.uri, 'ws://localhost:8181');
      expect(service.exposedUri, 'ws://forwarded-host:8181');
      expect(service.connectionUri, 'ws://forwarded-host:8181');
      expect(service.name, 'counter demo');
      expect(service.isAlive, isTrue);
      expect(service.autoReconnect, isTrue);
      expect(service.displayLabel, 'counter demo — ws://forwarded-host:8181');
    });

    test(
        'uses the service URI and default name when optional fields are absent',
        () {
      final service = DtdVmServiceInfo.fromFields(uri: 'ws://localhost:8181');

      expect(service.connectionUri, 'ws://localhost:8181');
      expect(service.displayLabel, 'VM Service — ws://localhost:8181');
      expect(service.autoReconnect, isFalse);
    });

    test('truncates long connection URIs in display labels only', () {
      final uri = 'ws://${'a' * 60}';
      final service = DtdVmServiceInfo.fromFields(uri: uri, name: 'long VM');

      expect(service.connectionUri, uri);
      expect(service.displayLabel, 'long VM — ${uri.substring(0, 50)}…');
    });
  });
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_connection_strategy.dart
// Platform-neutral contract for connecting to an ROHD VM service.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:vm_service/vm_service.dart';

/// Abstract base for VM connection strategies.
abstract class VmConnectionStrategy {
  /// Connects to a VM service at [uri].
  Future<VmConnectionResult> connect(String uri);

  /// Normalizes an HTTP or WebSocket endpoint to the VM WebSocket form.
  Uri? normalizeUri(String value) {
    try {
      var uri = Uri.parse(value.trim());
      if (uri.scheme == 'http') {
        uri = uri.replace(scheme: 'ws');
      } else if (uri.scheme == 'https') {
        uri = uri.replace(scheme: 'wss');
      }
      if (!uri.path.endsWith('/ws')) {
        uri = uri.replace(path: '${uri.path}ws');
      }
      return uri;
    } on FormatException {
      return null;
    }
  }
}

/// Result of a successful VM connection attempt.
class VmConnectionResult {
  /// Creates a connection result for [vmService] and its ROHD [isolateId].
  VmConnectionResult({required this.vmService, required this.isolateId});

  /// Connected VM service.
  final VmService vmService;

  /// Isolate that hosts the ROHD inspector service.
  final String isolateId;
}

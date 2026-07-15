// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// io_vm_connection_strategy.dart
// VM connection strategy for native (Linux/macOS/Windows) platforms.
// Uses vm_service_io for WebSocket connection.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Simple logging class for VM service.
class _StdoutLog extends Log {
  final Logger _logger = Logger('VMService');
  @override
  void warning(String message) => _logger.warning(message);

  @override
  void severe(String message) => _logger.severe(message);
}

/// VM connection strategy for native platforms (Linux/macOS/Windows).
/// Uses vm_service_io's vmServiceConnectUri.
class IoVmConnectionStrategy extends VmConnectionStrategy {
  @override

  /// Connects to a VM service on native platforms.
  Future<VmConnectionResult> connect(String uri) async {
    final normalizedUri = normalizeUri(uri);

    if (normalizedUri == null) {
      throw Exception('Invalid URI format');
    }

    final vmService = await vmServiceConnectUri(
      normalizedUri.toString(),
      log: _StdoutLog(),
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('VM connection timed out after 10 s'),
    );

    final vm = await vmService.getVM().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('getVM timed out after 5 s'),
        );

    // During a debugger restart the VM service endpoint becomes available
    // before isolates are created, and the test isolate (which contains
    // the ROHD inspector_service library) may lag behind the test-runner
    // control isolate.  Retry a few times with a short delay so we don't
    // fall back to the slow polling reconnect path.
    String? isolateId;
    const maxRetries = 6;
    const retryDelay = Duration(milliseconds: 500);

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      final vmInfo = attempt == 1
          ? vm
          : await vmService.getVM().timeout(const Duration(seconds: 3));
      final isolates = vmInfo.isolates ?? [];

      if (isolates.isEmpty) {
        if (attempt < maxRetries) {
          Logger('VMService').info(
            'No isolates yet (attempt $attempt/$maxRetries) — '
            'waiting ${retryDelay.inMilliseconds} ms',
          );
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw Exception(
          'No isolates found in the VM after $maxRetries '
          'attempts (${retryDelay.inMilliseconds * maxRetries} ms)',
        );
      }

      // Find the isolate that contains the ROHD inspector_service library.
      for (final isolateRef in isolates) {
        final id = isolateRef.id;
        if (id == null) {
          continue;
        }
        try {
          final isolate = await vmService
              .getIsolate(id)
              .timeout(const Duration(milliseconds: 500));
          final libraries = isolate.libraries ?? [];
          final hasRohd = libraries.any(
            (lib) =>
                lib.uri != null &&
                lib.uri!.contains('rohd') &&
                lib.uri!.contains('inspector_service'),
          );
          if (hasRohd) {
            isolateId = id;
            break;
          }
        } on Exception {
          // Isolate not loaded yet or timed out — skip it
          continue;
        }
      }

      if (isolateId != null) {
        break;
      }

      // Found isolates but none had ROHD — the test isolate may not
      // have spawned yet.  Retry unless this is the last attempt.
      if (attempt < maxRetries) {
        Logger('VMService').info(
          'ROHD isolate not found yet (attempt $attempt/$maxRetries, '
          '${isolates.length} isolate(s) seen) — retrying',
        );
        await Future<void>.delayed(retryDelay);
        continue;
      }

      // Last attempt — fall back to first isolate.
      final fallback = isolates.first.id;
      if (fallback == null) {
        throw Exception('First isolate has no ID');
      }
      isolateId = fallback;
      Logger('VMService').info(
        'Isolate library scan incomplete after $maxRetries attempts — '
        'using first isolate; evalModuleTree will verify',
      );
    }

    return VmConnectionResult(vmService: vmService, isolateId: isolateId!);
  }
}

/// Returns an [IoVmConnectionStrategy].  Used by the conditional-import
/// dispatcher in `platform_vm_connection_strategy.dart`.
VmConnectionStrategy platformVmConnectionStrategy() => IoVmConnectionStrategy();

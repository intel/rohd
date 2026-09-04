// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flc_extension_client.dart
// RohdExtensionClient implementation backed by the local FlcService.
//
// Used in DevTools-embedded mode and standalone mode when the app is
// connected to a running ROHD VM.  The FlcService fetches FLC trace data
// from the live isolate, so the extension is "always available" from the
// perspective of viewers embedded within the DevTools shell.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// [RohdExtensionClient] backed by a [FlcService].
///
/// Used in DevTools / standalone mode where the app already has a live
/// connection to the running ROHD VM and can fetch FLC data directly.
///
/// - [isAvailable] is always `true` once the client is constructed (the
///   DevTools shell is the "extension" in this context).
/// - [queryModule] fetches FLC data for the module and determines which
///   source formats are present.
///
/// File availability (whether the source file exists on disk) cannot be
/// checked from within the Flutter DevTools app — that is a VS Code
/// host concern.  [RohdFormatInfo.fileFound] is therefore always `true`
/// when the format is present in the FLC data (it was found at build time).
class FlcExtensionClient implements RohdExtensionClient {
  final FlcService _flcService;

  @override
  final isAvailable = ValueNotifier<bool>(true);

  @override
  final currentModuleInfo = ValueNotifier<RohdModuleInfo?>(null);

  /// Creates an extension client backed by [flcService].
  FlcExtensionClient({required FlcService flcService})
      : _flcService = flcService;

  @override
  Future<bool> ping() async {
    // The FlcService is in-process; always reachable.
    isAvailable.value = true;
    return true;
  }

  @override
  Future<RohdModuleInfo> queryModule(
    String module, {
    List<String>? instancePath,
  }) async {
    final fullPath = instancePath?.join('/') ?? '';
    debugPrint(
      '[CrossProbe] queryModule: "$module"'
      '${instancePath != null ? " instancePath=$fullPath" : ""}',
    );
    try {
      var formatKeys = await _flcService.getModuleFormats(module);
      debugPrint(
        '[CrossProbe] queryModule "$module": '
        'formats by class name = $formatKeys',
      );

      // If no formats found by the definition/class name, fall back to the
      // last non-empty segment of instancePath (the instance name).  This
      // handles the common case where FLC data is indexed by instance name
      // (e.g. "serializer") but the schematic passes the class name
      // (e.g. "Serializer") as the primary query key.
      if (formatKeys.isEmpty && instancePath != null) {
        final instanceName = instancePath.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        );
        if (instanceName.isNotEmpty && instanceName != module) {
          debugPrint(
            '[CrossProbe] queryModule "$module": '
            'trying instance name fallback "$instanceName"',
          );
          final fallbackKeys = await _flcService.getModuleFormats(instanceName);
          debugPrint(
            '[CrossProbe] queryModule fallback "$instanceName": '
            'formats = $fallbackKeys',
          );
          if (fallbackKeys.isNotEmpty) {
            formatKeys = fallbackKeys;
          }
        }
      }

      final formats = <RohdSourceFormat, RohdFormatInfo>{};

      for (final key in formatKeys) {
        final fmt = _parseFormat(key);
        if (fmt == null) {
          continue;
        }
        // Files were found at compile/trace time; we assume they're present.
        formats[fmt] = const RohdFormatInfo(available: true, fileFound: true);
      }

      debugPrint(
        '[CrossProbe] queryModule result: '
        'module="$module" '
        'formats=${formats.keys.map((f) => f.name).toList()}',
      );
      final info = RohdModuleInfo(
        extensionAvailable: true,
        module: module,
        formats: formats,
      );
      currentModuleInfo.value = info;
      return info;
    } on Exception catch (e) {
      debugPrint('[CrossProbe] queryModule "$module": ERROR $e');
      final info = RohdModuleInfo(
        extensionAvailable: true,
        module: module,
        error: e.toString(),
      );
      currentModuleInfo.value = info;
      return info;
    }
  }

  @override
  void dispose() {
    isAvailable.dispose();
    currentModuleInfo.dispose();
  }

  // In DevTools mode, frame lookup is handled locally by the embedding app
  // (confapp / devtools shell) via FlcData — not through this client.
  @override
  Future<List<Map<String, dynamic>>> lookupSignalFrames({
    required List<Map<String, String>> signals,
    String? format,
  }) async =>
      const [];

  @override
  void openSourceLocation({
    required String file,
    required int line,
    int col = 0,
  }) {
    // In DevTools mode, source navigation is handled by the embedding app.
    debugPrint(
      '[FlcExtensionClient] openSourceLocation: $file:$line:$col '
      '(no-op in DevTools mode)',
    );
  }

  static RohdSourceFormat? _parseFormat(String key) => switch (key) {
        'rohd' => RohdSourceFormat.rohd,
        'sv' => RohdSourceFormat.sv,
        'sc' => RohdSourceFormat.sc,
        'fst' => RohdSourceFormat.fst,
        _ => null,
      };
}

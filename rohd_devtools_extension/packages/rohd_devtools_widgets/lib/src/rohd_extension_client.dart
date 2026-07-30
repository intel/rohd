// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_extension_client.dart
// Abstract interface for querying the ROHD VS Code extension.
//
// Implemented by:
//   • FlcExtensionClient   — backed by FlcService (DevTools / standalone mode)
//   • VscodeExtensionClient — posts messages to the VS Code webview host
//   • NullExtensionClient   — no-op (fully offline / demo mode)
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
export 'rohd_extension_status.dart';
import 'rohd_extension_status.dart';

/// Abstract client for the ROHD VS Code extension handshake.
///
/// Both the schematic viewer and the wave viewer use this interface to:
///   1. Detect whether the extension is reachable ([ping]).
///   2. Query what source formats are available for a given module
///      ([queryModule]), triggering any necessary FST/VCD pre-loading.
///   3. Observe connection status and module info reactively via
///      [isAvailable] and [currentModuleInfo] notifiers.
abstract class RohdExtensionClient {
  /// Whether the ROHD extension is reachable.
  ///
  /// Updated after [ping] resolves and whenever the client detects a
  /// disconnection.  Viewers can listen to this notifier to show/hide
  /// a status icon.
  ValueNotifier<bool> get isAvailable;

  /// The most recently fetched [RohdModuleInfo], or `null` before the first
  /// [queryModule] call.
  ///
  /// Updated each time [queryModule] completes.  Viewers listen to this
  /// notifier to rebuild their "Go to …" menus.
  ValueNotifier<RohdModuleInfo?> get currentModuleInfo;

  /// Check whether the ROHD extension is running and reachable.
  ///
  /// Updates [isAvailable] and returns `true` on success.
  /// Safe to call repeatedly (e.g. on a timer for status polling).
  Future<bool> ping();

  /// Query what source formats the extension has for [module].
  ///
  /// [module] is the definition name of the module currently displayed
  /// (e.g. `'Counter_L1_'`).  [instancePath] is the optional instance
  /// path from the root (e.g. `['serializer', 'counter']`), which may
  /// help the extension locate waveform data.
  ///
  /// Returns a [RohdModuleInfo] describing what is available, and updates
  /// [currentModuleInfo] with the same value.
  ///
  /// Never throws — returns [RohdModuleInfo.unavailable] on error.
  Future<RohdModuleInfo> queryModule(
    String module, {
    List<String>? instancePath,
  });

  /// Look up source frames for [signals] via the extension host.
  ///
  /// [signals] is a list of maps with 'module' and 'name' keys.
  /// [format] is optional — 'rohd' or 'sv' to filter frame types.
  ///
  /// Returns a list of frame maps with keys: file, line, col, desc, type.
  /// Returns an empty list if no frames found or extension unavailable.
  Future<List<Map<String, dynamic>>> lookupSignalFrames({
    required List<Map<String, String>> signals,
    String? format,
  });

  /// Open a specific source location in the editor.
  ///
  /// Used after the user picks a frame from the popup selection.
  void openSourceLocation({
    required String file,
    required int line,
    int col = 0,
  });

  /// Release any resources held by this client.
  void dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
// Null implementation — used in fully standalone / demo mode.
// ─────────────────────────────────────────────────────────────────────────────

/// A no-op [RohdExtensionClient] used when no extension is reachable.
///
/// [isAvailable] is always `false`, [queryModule] always returns
/// [RohdModuleInfo.unavailable], and [ping] always returns `false`.
class NullExtensionClient implements RohdExtensionClient {
  @override
  final isAvailable = ValueNotifier<bool>(false);

  @override
  final currentModuleInfo = ValueNotifier<RohdModuleInfo?>(null);

  @override
  Future<bool> ping() async => false;

  @override
  Future<RohdModuleInfo> queryModule(
    String module, {
    List<String>? instancePath,
  }) async =>
      RohdModuleInfo.unavailable;

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
  }) {}

  @override
  void dispose() {
    isAvailable.dispose();
    currentModuleInfo.dispose();
  }
}

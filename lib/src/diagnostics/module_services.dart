// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_services.dart
// Singleton service registry for DevTools integration.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/diagnostics/inspector_service.dart';

/// Singleton service registry that provides a unified query surface for
/// DevTools and other inspection tools.
///
/// Services register themselves here on construction; DevTools evaluates
/// getters on [instance] via `EvalOnDartLibrary` to pull data.
///
/// **Auto-registered:**
///  - [rootModule] / [hierarchyJSON] — set by [Module.build].
///
/// **Opt-in (registered by service constructors):**
///  - [svService] — SystemVerilog synthesis results.
///
/// Additional services (netlist, trace, waveform) can be added by setting
/// the corresponding field after construction.
class ModuleServices {
  ModuleServices._();

  /// The singleton instance.
  static final ModuleServices instance = ModuleServices._();

  // ─── Hierarchy (auto-registered by Module.build) ──────────────

  /// The most recently built top-level [Module].
  ///
  /// Set automatically at the end of [Module.build].
  Module? rootModule;

  /// Returns the module hierarchy as a JSON string.
  ///
  /// DevTools evaluates this via `EvalOnDartLibrary` to display
  /// the module hierarchy.
  String get hierarchyJSON {
    ModuleTree.rootModuleInstance = rootModule;
    return ModuleTree.instance.hierarchyJSON;
  }

  /// Returns the primary inspector JSON for DevTools.
  ///
  /// Returns the hierarchy JSON.  Downstream branches (e.g. netlist) may
  /// override this to return richer data when available.
  String get inspectorJSON => hierarchyJSON;

  // ─── SystemVerilog service (opt-in) ───────────────────────────

  /// The active [SvService], if one has been registered.
  SvService? svService;

  /// Returns SV synthesis metadata as JSON, or an unavailable status.
  String get svJSON => svService != null
      ? jsonEncode(svService!.toJson())
      : _unavailable('sv');

  // ─── Helpers ──────────────────────────────────────────────────

  static String _unavailable(String service) => jsonEncode(<String, String>{
        'status': 'unavailable',
        'reason': '$service service not registered',
      });

  /// Resets all services.  Intended for test teardown.
  void reset() {
    rootModule = null;
    svService = null;
  }
}

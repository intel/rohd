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
///  - [netlistService] — Yosys-format netlist JSON.
///
/// Additional services (trace, waveform) can be added by setting the
/// corresponding field after construction.
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

  /// Returns the unified inspector JSON — the primary entry point for
  /// DevTools to load the design.
  ///
  /// When a [NetlistService] is registered, this returns the slim netlist
  /// (hierarchy + ports + cells without connectivity).
  ///
  /// Falls back to the hierarchy JSON when no netlist service is available.
  String get inspectorJSON {
    if (netlistService != null) {
      return netlistService!.slimJson;
    }
    return hierarchyJSON;
  }

  /// Returns the full netlist JSON for a single module definition.
  ///
  /// When a [NetlistService] is registered, returns the per-module netlist
  /// (with full connectivity).
  String inspectorModuleJSON(String definitionName) {
    if (netlistService != null) {
      return netlistService!.moduleJson(definitionName);
    }
    return _unavailable('netlist');
  }

  // ─── SystemVerilog service (opt-in) ───────────────────────────

  /// The active [SvService], if one has been registered.
  SvService? svService;

  /// Returns SV synthesis metadata as JSON, or an unavailable status.
  String get svJSON =>
      svService != null ? jsonEncode(svService!.toJson()) : _unavailable('sv');

  // ─── Netlist service (opt-in) ─────────────────────────────────

  /// The active [NetlistService], if one has been registered.
  NetlistService? netlistService;

  /// Returns the full netlist hierarchy as JSON, or an unavailable status.
  String get netlistJSON => netlistService != null
      ? netlistService!.toJson()
      : _unavailable('netlist');

  /// Returns the netlist for a single module definition, or unavailable.
  String netlistModuleJSON(String definitionName) => netlistService != null
      ? netlistService!.moduleJson(definitionName)
      : _unavailable('netlist');

  // ─── Helpers ──────────────────────────────────────────────────

  static String _unavailable(String service) => jsonEncode(<String, String>{
        'status': 'unavailable',
        'reason': '$service service not registered',
      });

  /// Resets all services.  Intended for test teardown.
  void reset() {
    rootModule = null;
    svService = null;
    netlistService = null;
  }
}

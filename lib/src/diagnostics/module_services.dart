// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_services.dart
// Singleton service registry for DevTools integration.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';

/// The read-only netlist surface used by [ModuleServices].
///
/// Feature branches provide concrete implementations without making this
/// package layer depend on netlist synthesis classes.
abstract interface class NetlistInspectionService {
  /// Returns a compact hierarchy-oriented netlist JSON string.
  String get slimJson;

  /// Returns the full netlist hierarchy JSON string.
  String toJson();

  /// Returns netlist JSON for a single module [definitionName].
  String moduleJson(String definitionName);
}

/// The read-only source-trace surface used by [ModuleServices].
///
/// Feature branches provide concrete implementations without making this
/// package layer depend on source-debug tracing classes.
abstract interface class TraceInspectionService {
  /// The top-level module associated with this trace.
  Module get module;

  /// Returns the FLC hierarchy object, or `null` when unavailable.
  Map<String, Object>? get flcHierarchy;

  /// Returns the full FLC hierarchy JSON string.
  String get flcJson;

  /// Returns FLC JSON for a single module [definitionName].
  String flcModuleJson(String definitionName);
}

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
///  - [netlistService] — netlist inspection data.
///  - [waveformService] — waveform capture (file output + optional streaming).
///  - [traceService] — source trace / FLC data.
///
/// Concrete feature services implement the small inspection interfaces above,
/// so this branch stays a formal dependency without importing future feature
/// branches.
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

  /// Returns the unified inspector JSON, the primary DevTools design entry
  /// point.
  ///
  /// When a netlist inspection service is registered, this returns the compact
  /// netlist view. Otherwise it falls back to the module hierarchy JSON.
  String get inspectorJSON => netlistService?.slimJson ?? hierarchyJSON;

  /// Returns full inspector JSON for a single module [definitionName].
  String inspectorModuleJSON(String definitionName) =>
      netlistModuleJSON(definitionName);

  // ─── SystemVerilog service (opt-in) ───────────────────────────

  /// The active [SvService], if one has been registered.
  SvService? svService;

  /// Returns SV synthesis metadata as JSON, or an unavailable status.
  String get svJSON =>
      svService != null ? jsonEncode(svService!.toJson()) : _unavailable('sv');

  // ─── Netlist service (opt-in) ─────────────────────────────────

  /// The active netlist inspection service, if one has been registered.
  NetlistInspectionService? netlistService;

  /// Returns the full netlist hierarchy as JSON, or an unavailable status.
  String get netlistJSON => netlistService != null
      ? netlistService!.toJson()
      : _unavailable('netlist');

  /// Returns netlist JSON for a single module [definitionName].
  String netlistModuleJSON(String definitionName) => netlistService != null
      ? netlistService!.moduleJson(definitionName)
      : _unavailable('netlist');

  // ─── Waveform service (opt-in) ───────────────────────────────

  /// The active [WaveformService], if one has been registered.
  WaveformService? waveformService;

  /// Returns waveform service metadata as JSON, or an unavailable status.
  String get waveformJSON => waveformService != null
      ? jsonEncode(waveformService!.toJson())
      : _unavailable('waveform');

  // ─── Trace service (opt-in) ───────────────────────────────────

  /// The active source-trace inspection service, if one has been registered.
  TraceInspectionService? traceService;

  /// Cached path to the FLC file written by [flcFilePath].
  String? _flcFilePathCache;

  /// Returns the FLC hierarchy JSON, or an unavailable status.
  String get flcJSON =>
      traceService != null ? traceService!.flcJson : _unavailable('trace');

  /// Returns FLC JSON for a single module [definitionName].
  String flcModuleJSON(String definitionName) => traceService != null
      ? traceService!.flcModuleJson(definitionName)
      : _unavailable('trace');

  /// Writes the FLC hierarchy to a temporary file and returns the path.
  ///
  /// Returns a JSON error string when trace data is unavailable or the write
  /// fails.
  String get flcFilePath {
    if (_flcFilePathCache != null) {
      if (File(_flcFilePathCache!).existsSync()) {
        return _flcFilePathCache!;
      }
      _flcFilePathCache = null;
    }

    final service = traceService;
    if (service == null) {
      return _unavailable('trace');
    }
    final hierarchy = service.flcHierarchy;
    if (hierarchy == null) {
      return _unavailable('trace');
    }

    try {
      final dir = Directory('${Directory.systemTemp.path}/rohd_devtools_flc')
        ..createSync(recursive: true);
      final path = '${dir.path}/${service.module.definitionName}.flc.json';
      File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(hierarchy),
      );
      _flcFilePathCache = path;
      return path;
    } on Exception catch (error) {
      return jsonEncode(<String, String>{
        'status': 'error',
        'reason': error.toString(),
      });
    }
  }

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
    waveformService = null;
    traceService = null;
    _flcFilePathCache = null;
  }
}

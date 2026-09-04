// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_service.dart
// Services for tree logic.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:convert';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:vm_service/vm_service.dart';

/// Service for managing the module tree.
class TreeService {
  /// Unified format containing hierarchy + optional schematic.
  static const _unifiedFunc = 'NetlistService.current?.slimJson ?? '
      'ModuleServices.instance.hierarchyJson';

  /// The ROHD controller eval instance.
  final EvalOnDartLibrary rohdControllerEval;

  /// The disposable to check if the eval is still alive.
  final Disposable evalDisposable;

  /// Cached schematic JSON from the last eval/refresh.
  Map<String, dynamic>? _cachedSchematicJson;

  /// Cached FLC hierarchy JSON, keyed by module definition name.
  final Map<String, Map<String, dynamic>> _cachedFlcJson = {};

  /// Optional VM service for source-line lookups (cross-probe).
  final VmService? vmService;

  /// Optional isolate ID used with [vmService] for source-line lookups.
  final String? isolateId;

  /// Cached script source text, keyed by the file URI used to look it up.
  final _scriptSourceCache = <String, String?>{};

  /// Cached list of [ScriptRef]s for the [isolateId].
  List<ScriptRef>? _scriptRefs;

  /// Creates a [TreeService] with the given ROHD controller eval and
  /// disposable.
  ///
  /// Optionally accepts a [vmService] + [isolateId] pair, which enables
  /// [fetchSourceLine] for cross-probe source-line enrichment.
  TreeService(
    this.rohdControllerEval,
    this.evalDisposable, {
    this.vmService,
    this.isolateId,
  });

  /// Get the cached schematic JSON from the last eval/refresh.
  /// Returns null if no schematic data is available or hasn't been loaded yet.
  Map<String, dynamic>? getSchematicJson() => _cachedSchematicJson;

  /// Evaluate the module tree from the connected ROHD application.
  ///
  /// Evaluates `NetlistService.current?.slimJson` (falling back to
  /// `ModuleServices.instance.hierarchyJson`) which returns a unified
  /// netlist format containing hierarchy and schematic data.
  Future<TreeModel> evalModuleTree() async {
    final instance = await rohdControllerEval.evalInstance(
      _unifiedFunc,
      isAlive: evalDisposable,
    );
    final json =
        jsonDecode(instance.valueAsString ?? '{}') as Map<String, dynamic>;
    if (json['status'] == 'fail') {
      throw StateError('Failed to evaluate module tree');
    }
    final designData = DesignDataAdapter.parseJson(json);
    _cachedSchematicJson = designData.schematicJson;
    return designData.hierarchy.root;
  }

  /// Refresh the module tree from the connected ROHD application.
  ///
  /// Uses the same unified → fallback strategy as [evalModuleTree].
  Future<TreeModel> refreshModuleTree() => evalModuleTree();

  /// Fetch the full schematic JSON for a single module definition.
  ///
  /// Evaluates `NetlistService.current?.moduleJson('name')` in the
  /// connected ROHD application.  Returns `null` when the module is not
  /// found or incremental data is unavailable.
  Future<Map<String, dynamic>?> fetchModuleSchematic(
    String definitionName,
  ) async {
    try {
      // Sanitize to prevent injection in the eval expression.
      final safeName = definitionName.replaceAll("'", r"\'");
      final expr = "NetlistService.current?.moduleJson('$safeName')";
      final instance = await rohdControllerEval.evalInstance(
        expr,
        isAlive: evalDisposable,
      );
      final raw = instance.valueAsString;
      if (raw == null || raw == 'null') {
        debugPrint(
          '[INCREMENTAL][TreeService] fetchModuleSchematic: '
          '"$definitionName" — returned null',
        );
        return null;
      }
      debugPrint(
        '[INCREMENTAL][TreeService] fetchModuleSchematic: '
        '"$definitionName" → '
        '${(raw.length / 1024).toStringAsFixed(1)} KB',
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // New format wraps module data under a 'modules' key.
      if (decoded.containsKey('modules') &&
          !decoded.containsKey(definitionName)) {
        return decoded['modules'] as Map<String, dynamic>;
      }
      return decoded;
    } on Exception catch (e) {
      debugPrint(
        '[INCREMENTAL][TreeService] fetchModuleSchematic '
        'error: $e',
      );
      return null;
    }
  }

  /// Fetch FLC (File-Line-Column) data for a single module definition.
  ///
  /// Evaluates the registered FlcService in the connected ROHD application.
  /// Returns `null` when the FLC service is not registered or the module has
  /// no FLC data.
  ///
  /// Results are cached per module definition name.
  Future<Map<String, dynamic>?> fetchModuleFlc(String definitionName) async {
    // Return cached if available.
    final cached = _cachedFlcJson[definitionName];
    if (cached != null) {
      return cached;
    }

    try {
      final safeName = definitionName.replaceAll("'", r"\'");
      final expr = "TraceService.current?.flcModuleJson('$safeName') ?? "
          "'{\"status\":\"unavailable\"}'";
      final instance = await rohdControllerEval.evalInstance(
        expr,
        isAlive: evalDisposable,
      );
      final raw = instance.valueAsString;
      if (raw == null || raw == 'null') {
        debugPrint(
          '[TreeService] fetchModuleFlc: '
          '"$definitionName" — returned null',
        );
        return null;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;

      // Check for unavailable status.
      if (json['status'] == 'unavailable') {
        debugPrint(
          '[TreeService] fetchModuleFlc: '
          '"$definitionName" — ${json['reason']}',
        );
        return null;
      }

      debugPrint(
        '[TreeService] fetchModuleFlc: '
        '"$definitionName" → '
        '${(raw.length / 1024).toStringAsFixed(1)} KB',
      );
      _cachedFlcJson[definitionName] = json;
      return json;
    } on Exception catch (e) {
      debugPrint('[TreeService] fetchModuleFlc error: $e');
      return null;
    }
  }

  /// Fetch FLC data for the full module hierarchy.
  ///
  /// Evaluates the registered FLC provider in the connected app.
  Future<Map<String, dynamic>?> fetchFlcHierarchy() async {
    try {
      const expr = 'TraceService.current?.flcJson ?? '
          "'{\"status\":\"unavailable\"}'";
      final instance = await rohdControllerEval.evalInstance(
        expr,
        isAlive: evalDisposable,
      );
      final raw = instance.valueAsString;
      if (raw == null || raw == 'null') {
        return null;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['status'] == 'unavailable') {
        debugPrint('[TreeService] fetchFlcHierarchy: ${json['reason']}');
        return null;
      }
      debugPrint(
        '[TreeService] fetchFlcHierarchy: '
        '${(raw.length / 1024).toStringAsFixed(1)} KB',
      );
      return json;
    } on Exception catch (e) {
      debugPrint('[TreeService] fetchFlcHierarchy error: $e');
      return null;
    }
  }

  /// Clear all cached FLC data.
  ///
  /// Call on VM disconnect or debug restart so stale data is not reused.
  void clearFlcCache() {
    _cachedFlcJson.clear();
    _scriptSourceCache.clear();
    _scriptRefs = null;
    debugPrint('[TreeService] FLC cache cleared');
  }

  /// Fetch the source line for a given file URI and line number.
  ///
  /// [fileUri] is the package-relative path from FLC (e.g.
  /// `lib/src/counter.dart`).  Internally we search for a matching Script
  /// in the isolate and retrieve its source text.
  ///
  /// Returns `null` if [vmService]/[isolateId] are not set, the script
  /// cannot be found, or the line is out of range.
  Future<String?> fetchSourceLine(String fileUri, int line) async {
    if (vmService == null || isolateId == null) {
      return null;
    }
    try {
      final source = await _getScriptSource(fileUri);
      if (source == null) {
        return null;
      }
      final lines = source.split('\n');
      if (line < 1 || line > lines.length) {
        return null;
      }
      return lines[line - 1];
    } on Exception catch (e) {
      debugPrint('[TreeService] fetchSourceLine error: $e');
      return null;
    }
  }

  /// Get cached script source, fetching from VM service if needed.
  Future<String?> _getScriptSource(String fileUri) async {
    if (_scriptSourceCache.containsKey(fileUri)) {
      return _scriptSourceCache[fileUri];
    }
    final svc = vmService!;
    final isoId = isolateId!;

    _scriptRefs ??= (await svc.getScripts(isoId)).scripts ?? [];

    final normalized = _normalizePath(fileUri);
    String suffix;
    final libIdx = normalized.lastIndexOf('lib/');
    if (libIdx >= 0) {
      suffix = normalized.substring(libIdx + 4);
    } else {
      suffix = normalized.split('/').last;
    }

    final ref = _scriptRefs!.cast<ScriptRef?>().firstWhere((s) {
      final uri = s!.uri;
      if (uri == null) {
        return false;
      }
      return uri.endsWith(suffix);
    }, orElse: () => null);

    if (ref == null || ref.id == null) {
      debugPrint(
        '[TreeService] _getScriptSource: '
        'no script matching "$fileUri" (normalized: "$normalized", '
        'suffix: "$suffix")',
      );
      _scriptSourceCache[fileUri] = null;
      return null;
    }

    final obj = await svc.getObject(isoId, ref.id!);
    if (obj is Script && obj.source != null) {
      _scriptSourceCache[fileUri] = obj.source;
      return obj.source;
    }

    debugPrint(
      '[TreeService] _getScriptSource: '
      'no source in script for "$fileUri"',
    );
    _scriptSourceCache[fileUri] = null;
    return null;
  }

  /// Normalize a relative file path by resolving `..` segments.
  ///
  /// e.g. `.dart_tool/../lib/src/counter.dart` → `lib/src/counter.dart`
  static String _normalizePath(String path) {
    final segments = path.split('/');
    final resolved = <String>[];
    for (final seg in segments) {
      if (seg == '..') {
        if (resolved.isNotEmpty) {
          resolved.removeLast();
        }
      } else if (seg != '.' && seg.isNotEmpty) {
        resolved.add(seg);
      }
    }
    return resolved.join('/');
  }

  /// Fetch the path to the FLC file on disk for the running ROHD app.
  ///
  /// Evaluates the registered FlcService for the absolute path of the FLC
  /// hierarchy file written to disk. Returns `null` when the FLC service is
  /// not registered or nothing has been written.
  Future<String?> fetchFlcFilePath() async {
    try {
      const expr = 'TraceService.current?.writtenPath';
      final instance = await rohdControllerEval.evalInstance(
        expr,
        isAlive: evalDisposable,
      );
      final raw = instance.valueAsString;
      if (raw == null || raw == 'null' || raw.startsWith('{')) {
        debugPrint('[TreeService] fetchFlcFilePath: unavailable: $raw');
        return null;
      }
      debugPrint('[TreeService] fetchFlcFilePath: $raw');
      return raw;
    } on Exception catch (e) {
      debugPrint('[TreeService] fetchFlcFilePath error: $e');
      return null;
    }
  }
}

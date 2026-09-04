// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_tree_data_source.dart
// VM service-based tree data source for DTD/debugger connection.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_data_source.dart';
import 'package:vm_service/vm_service.dart';

/// VM service-based tree data source for connecting to running ROHD apps.
///
/// This connects via the Dart VM service protocol to evaluate
/// `NetlistService.current?.slimJson` (unified netlist format) in the
/// target application. The result goes through [DesignDataAdapter] which
/// extracts the hierarchy and any embedded schematic data in a single pass.
class VmServiceTreeDataSource implements TreeDataSource {
  final VmService _vmService;
  final String _isolateId;

  static const _unifiedFunc = 'NetlistService.current?.slimJson ?? '
      'ModuleServices.instance.hierarchyJson';

  /// Cached schematic JSON from the last eval/refresh.
  Map<String, dynamic>? _cachedSchematicJson;

  /// Creates a [VmServiceTreeDataSource] with the given VM service and isolate
  /// ID.
  VmServiceTreeDataSource({
    required VmService vmService,
    required String isolateId,
  })  : _vmService = vmService,
        _isolateId = isolateId;

  @override
  bool get isConnected => true; // Assumed connected if this object exists

  @override
  String get modeDescription => 'VM Service (DTD)';

  @override
  Map<String, dynamic>? getSchematicJson() => _cachedSchematicJson;

  @override
  Future<TreeModel?> evalModuleTree() async {
    try {
      debugPrint('[VmServiceTreeDataSource] Getting isolate $_isolateId...');
      final isolate = await _vmService.getIsolate(_isolateId);
      final libraries = isolate.libraries ?? [];
      debugPrint(
        '[VmServiceTreeDataSource] Found ${libraries.length} libraries',
      );

      LibraryRef? rohdLibRef;
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null &&
            uri.contains('rohd') &&
            (uri.contains('module_services') ||
                uri.contains('inspector_service'))) {
          rohdLibRef = libRef;
          debugPrint('[VmServiceTreeDataSource] Found ROHD library: $uri');
          break;
        }
      }

      // Fallback to module_tree library
      rohdLibRef ??= libraries.cast<LibraryRef?>().firstWhere((libRef) {
        final uri = libRef?.uri;
        return uri != null &&
            uri.contains('rohd') &&
            uri.contains('module_tree');
      }, orElse: () => null);

      // Broader fallbacks: match common ROHD-related URI patterns. This helps
      // when the inspector helpers are compiled into a different library
      // (for example when files are re-exported or combined by the test
      // harness).
      rohdLibRef ??= libraries.cast<LibraryRef?>().firstWhere((libRef) {
        final uri = libRef?.uri;
        if (uri == null) {
          return false;
        }
        final lower = uri.toLowerCase();
        return lower.contains('package:rohd') ||
            lower.contains('/packages/rohd') ||
            lower.contains('rohd.dart') ||
            lower.contains('rohd/');
      }, orElse: () => null);

      if (rohdLibRef == null) {
        debugPrint(
          '[VmServiceTreeDataSource] No ROHD library found! Sample libraries:',
        );
        for (var i = 0; i < libraries.length && i < 20; i++) {
          debugPrint('  [lib $i] ${libraries[i].uri}');
        }
        return null;
      }

      // Evaluate unified netlist format
      debugPrint('[VmServiceTreeDataSource] Evaluating: $_unifiedFunc');
      final result = await _vmService.evaluate(
        _isolateId,
        rohdLibRef.id!,
        _unifiedFunc,
      );
      debugPrint(
        '[VmServiceTreeDataSource] Result type: '
        '${result.runtimeType}',
      );
      return await _parseResult(result);
    } on Exception catch (e, stack) {
      debugPrint('[VmServiceTreeDataSource] Error: $e');
      debugPrint('[VmServiceTreeDataSource] Stack: $stack');
      return null;
    }
  }

  /// Get the full string value from an InstanceRef. The VM service truncates
  /// valueAsString, so we need to fetch the full object.
  Future<String?> _getFullString(InstanceRef instanceRef) async {
    // Check if the string is truncated
    if (instanceRef.valueAsStringIsTruncated ?? false) {
      debugPrint(
        '[VmServiceTreeDataSource] String is truncated, '
        'fetching full object...',
      );
      try {
        final fullObject = await _vmService.getObject(
          _isolateId,
          instanceRef.id!,
        );
        if (fullObject is Instance) {
          debugPrint(
            '[VmServiceTreeDataSource] Got full string, length: '
            '${fullObject.valueAsString?.length}',
          );
          return fullObject.valueAsString;
        }
      } on Exception catch (e) {
        debugPrint('[VmServiceTreeDataSource] Failed to get full string: $e');
      }
    }
    return instanceRef.valueAsString;
  }

  @override
  Future<Map<String, dynamic>?> fetchModuleSchematic(
    String definitionName,
  ) async {
    try {
      final isolate = await _vmService.getIsolate(_isolateId);
      final libraries = isolate.libraries ?? [];

      LibraryRef? rohdLibRef;
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null &&
            uri.contains('rohd') &&
            (uri.contains('module_services') ||
                uri.contains('inspector_service') ||
                uri.contains('module_tree'))) {
          rohdLibRef = libRef;
          break;
        }
      }
      if (rohdLibRef == null) {
        return null;
      }

      // Sanitize to prevent injection in the eval expression.
      final safeName = definitionName.replaceAll("'", r"\'");
      final expr = "NetlistService.current?.moduleJson('$safeName')";
      final result = await _vmService.evaluate(
        _isolateId,
        rohdLibRef.id!,
        expr,
      );
      if (result is InstanceRef) {
        final raw = await _getFullString(result);
        if (raw == null || raw == 'null') {
          return null;
        }
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        // New format wraps module data under a 'modules' key.
        if (decoded.containsKey('modules') &&
            !decoded.containsKey(definitionName)) {
          return decoded['modules'] as Map<String, dynamic>;
        }
        return decoded;
      }
      return null;
    } on Exception catch (e) {
      debugPrint('[VmServiceTreeDataSource] fetchModuleSchematic error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // FLC (First-Level Callers) data for source cross-probing
  // ---------------------------------------------------------------------------

  /// Cached FLC JSON per module definition name.
  final Map<String, Map<String, dynamic>> _cachedFlcJson = {};

  /// Fetch FLC data for a single module definition.
  ///
  /// Evaluates the registered FLC provider on the running ROHD app.
  Future<Map<String, dynamic>?> fetchModuleFlc(String definitionName) async {
    if (_cachedFlcJson.containsKey(definitionName)) {
      return _cachedFlcJson[definitionName];
    }
    try {
      final libRef = await _findRohdLibrary();
      if (libRef == null) {
        debugPrint(
          '[VmServiceTreeDataSource] fetchModuleFlc: '
          'no ROHD library found for $definitionName',
        );
        return null;
      }

      final safeName = definitionName.replaceAll("'", r"\'");
      final expr = "TraceService.current?.flcModuleJson('$safeName') ?? "
          "'{\"status\":\"unavailable\"}'";
      debugPrint(
        '[VmServiceTreeDataSource] fetchModuleFlc: '
        'evaluating on ${libRef.uri}',
      );
      final result = await _vmService.evaluate(_isolateId, libRef.id!, expr);
      if (result is InstanceRef) {
        final raw = await _getFullString(result);
        if (raw == null || raw == 'null') {
          debugPrint(
            '[VmServiceTreeDataSource] fetchModuleFlc: '
            'null for $definitionName',
          );
          return null;
        }
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _cachedFlcJson[definitionName] = json;
        debugPrint(
          '[VmServiceTreeDataSource] fetchModuleFlc: '
          '${raw.length} chars for $definitionName',
        );
        return json;
      }
      debugPrint(
        '[VmServiceTreeDataSource] fetchModuleFlc: '
        'unexpected result type ${result.runtimeType} for $definitionName',
      );
      return null;
    } on Exception catch (e) {
      debugPrint('[VmServiceTreeDataSource] fetchModuleFlc error: $e');
      return null;
    }
  }

  /// Fetch the full FLC hierarchy JSON.
  ///
  /// Evaluates the registered [FlcService] on the running ROHD app.
  Future<Map<String, dynamic>?> fetchFlcHierarchy() async {
    try {
      final libRef = await _findRohdLibrary();
      if (libRef == null) {
        debugPrint(
          '[VmServiceTreeDataSource] fetchFlcHierarchy: '
          'no ROHD library found',
        );
        return null;
      }

      debugPrint(
        '[VmServiceTreeDataSource] fetchFlcHierarchy: '
        'evaluating on ${libRef.uri}',
      );
      final result = await _vmService.evaluate(
        _isolateId,
        libRef.id!,
        "TraceService.current?.flcJson ?? '{\"status\":\"unavailable\"}'",
      );
      if (result is InstanceRef) {
        final raw = await _getFullString(result);
        if (raw == null || raw == 'null') {
          debugPrint(
            '[VmServiceTreeDataSource] fetchFlcHierarchy: '
            'eval returned null',
          );
          return null;
        }
        debugPrint(
          '[VmServiceTreeDataSource] fetchFlcHierarchy: '
          '${raw.length} chars',
        );
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['status'] == 'unavailable') {
          debugPrint(
            '[VmServiceTreeDataSource] fetchFlcHierarchy: '
            '${json['reason'] ?? 'unavailable'}',
          );
          return null;
        }
        return json;
      }
      debugPrint(
        '[VmServiceTreeDataSource] fetchFlcHierarchy: '
        'unexpected result type ${result.runtimeType}',
      );
      return null;
    } on Exception catch (e) {
      debugPrint('[VmServiceTreeDataSource] fetchFlcHierarchy error: $e');
      return null;
    }
  }

  /// Fetch the path to the FLC file on disk for the running ROHD app.
  ///
  /// Evaluates the registered [FlcService] on the running ROHD app for
  /// the absolute path of the FLC hierarchy file written to disk.
  /// Returns `null` when the FLC service is not registered or nothing has
  /// been written.
  Future<String?> fetchFlcFilePath() async {
    try {
      final libRef = await _findRohdLibrary();
      if (libRef == null) {
        debugPrint(
          '[VmServiceTreeDataSource] fetchFlcFilePath: no ROHD library found',
        );
        return null;
      }
      final result = await _vmService.evaluate(
        _isolateId,
        libRef.id!,
        'TraceService.current?.writtenPath',
      );
      if (result is InstanceRef) {
        final raw = await _getFullString(result);
        if (raw == null || raw == 'null' || raw.startsWith('{')) {
          debugPrint(
            '[VmServiceTreeDataSource] fetchFlcFilePath: '
            'error/unavailable: $raw',
          );
          return null;
        }
        debugPrint('[VmServiceTreeDataSource] fetchFlcFilePath: $raw');
        return raw;
      }
      return null;
    } on Exception catch (e) {
      debugPrint('[VmServiceTreeDataSource] fetchFlcFilePath error: $e');
      return null;
    }
  }

  /// Clear cached FLC data.
  void clearFlcCache() {
    _cachedFlcJson.clear();
    _scriptCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Source line prefix extraction
  // ---------------------------------------------------------------------------

  /// Cache of script source text, keyed by script URI.
  final _scriptCache = <String, String?>{};

  /// Cached script list for the isolate.
  List<ScriptRef>? _scriptRefs;

  /// Fetch the source line for a given file URI and line number.
  ///
  /// [fileUri] is the package-relative path from FLC (e.g.
  /// `lib/src/counter.dart`). Internally we search for a matching Script
  /// in the isolate and retrieve its source text.
  ///
  /// Returns `null` if the script cannot be found or the line is out of range.
  Future<String?> fetchSourceLine(String fileUri, int line) async {
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
      debugPrint('[VmServiceTreeDataSource] fetchSourceLine error: $e');
      return null;
    }
  }

  /// Get cached script source, fetching from VM service if needed.
  Future<String?> _getScriptSource(String fileUri) async {
    if (_scriptCache.containsKey(fileUri)) {
      return _scriptCache[fileUri];
    }

    // Find the matching ScriptRef.
    _scriptRefs ??= (await _vmService.getScripts(_isolateId)).scripts ?? [];

    // FLC paths may contain relative segments like ".dart_tool/../lib/...".
    // Normalize by resolving ".." and then extracting a useful suffix.
    final normalized = _normalizePath(fileUri);

    // Extract the part after "lib/" — this maps to the package URI path.
    // e.g. "lib/src/counter.dart" → "src/counter.dart"
    // For cross-package paths, use the filename as last resort.
    String suffix;
    final libIdx = normalized.lastIndexOf('lib/');
    if (libIdx >= 0) {
      suffix = normalized.substring(libIdx + 4);
    } else {
      // No "lib/" — use the filename.
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
        '[VmServiceTreeDataSource] _getScriptSource: '
        'no script matching "$fileUri" (normalized: "$normalized", '
        'suffix: "$suffix")',
      );
      return null;
    }

    final obj = await _vmService.getObject(_isolateId, ref.id!);
    if (obj is Script && obj.source != null) {
      _scriptCache[fileUri] = obj.source;
      return obj.source!;
    }

    debugPrint(
      '[VmServiceTreeDataSource] _getScriptSource: '
      'no source in script for "$fileUri"',
    );
    return null;
  }

  @override
  Future<TreeModel?> refreshModuleTree() => evalModuleTree();

  @override
  Future<void> dispose() async {
    // Don't dispose the VM service here - caller manages its lifecycle
  }

  /// Find a ROHD library in the isolate for eval.
  ///
  /// Uses the same cascade of patterns as [evalModuleTree] so that FLC
  /// fetches work even when the inspector helpers live in a re-exported
  /// or combined library.
  Future<LibraryRef?> _findRohdLibrary() async {
    final isolate = await _vmService.getIsolate(_isolateId);
    final libraries = isolate.libraries ?? [];

    // Prefer module_services, inspector_service or module_tree.
    LibraryRef? ref;
    for (final libRef in libraries) {
      final uri = libRef.uri;
      if (uri != null &&
          uri.contains('rohd') &&
          (uri.contains('module_services') ||
              uri.contains('inspector_service') ||
              uri.contains('module_tree'))) {
        ref = libRef;
        break;
      }
    }

    // Broader fallback: any ROHD-related library (matches evalModuleTree).
    ref ??= libraries.cast<LibraryRef?>().firstWhere((libRef) {
      final uri = libRef?.uri;
      if (uri == null) {
        return false;
      }
      final lower = uri.toLowerCase();
      return lower.contains('package:rohd') ||
          lower.contains('/packages/rohd') ||
          lower.contains('rohd.dart') ||
          lower.contains('rohd/');
    }, orElse: () => null);

    if (ref == null) {
      debugPrint(
        '[VmServiceTreeDataSource] _findRohdLibrary: '
        'no ROHD library found among ${libraries.length} libraries',
      );
    }
    return ref;
  }

  Future<TreeModel?> _parseResult(Response result) async {
    if (result is InstanceRef) {
      // Get the full string - VM service truncates by default
      final valueStr = await _getFullString(result);
      debugPrint(
        '[VmServiceTreeDataSource] Full string length: '
        '${valueStr?.length ?? 0}',
      );
      if (valueStr == null) {
        debugPrint('[VmServiceTreeDataSource] valueAsString is null');
        return null;
      }

      try {
        final treeObj = jsonDecode(valueStr) as Map<String, dynamic>;
        debugPrint(
          '[VmServiceTreeDataSource] Parsed JSON, status: '
          '${treeObj['status']}',
        );

        if (treeObj['status'] == 'fail') {
          debugPrint(
            '[VmServiceTreeDataSource] Status is fail: '
            '${treeObj['message']}',
          );
          return null;
        }

        // Use DesignDataAdapter which handles both hierarchy and schematic
        // formats
        try {
          final designData = DesignDataAdapter.parseJson(treeObj);
          debugPrint(
            '[VmServiceTreeDataSource] Parsed as ${designData.format} '
            'format',
          );

          if (designData.hasSchematic) {
            debugPrint(
              '[VmServiceTreeDataSource] Schematic data available for '
              'visualization',
            );
            _cachedSchematicJson = designData.schematicJson;
          } else {
            _cachedSchematicJson = null;
          }

          final model = designData.hierarchy.root;
          debugPrint(
            '[VmServiceTreeDataSource] Successfully created TreeModel',
          );
          return model;
        } on FormatException catch (e) {
          debugPrint('[VmServiceTreeDataSource] DesignDataAdapter failed: $e');
          return null;
        }
      } on Exception catch (e) {
        debugPrint('[VmServiceTreeDataSource] Parse error: $e');
        return null;
      }
    } else if (result is ErrorRef) {
      debugPrint('[VmServiceTreeDataSource] ErrorRef: ${result.message}');
      return null;
    }
    debugPrint(
      '[VmServiceTreeDataSource] Unknown result type: ${result.runtimeType}',
    );
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
}

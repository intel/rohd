// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// yosys_loader_web.dart
// JS/Node implementation using direct JS interop to call d3-yosys.

// ignore_for_file: avoid_print

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Result of running the Yosys loader.
class YosysLoaderResult {
  /// Whether the load was successful.
  final bool success;

  /// Number of root children modules.
  final int? rootChildren;

  /// Top node ID.
  final String? topNodeId;

  /// Number of top node ports.
  final int? topNodePorts;

  /// Error message if unsuccessful.
  final String? error;

  /// Stack trace if available.
  final String? stack;

  /// Creates a [YosysLoaderResult].
  YosysLoaderResult({
    required this.success,
    this.rootChildren,
    this.topNodeId,
    this.topNodePorts,
    this.error,
    this.stack,
  });

  /// Creates a [YosysLoaderResult] from JSON map [j].
  factory YosysLoaderResult.fromJson(Map<String, dynamic> j) =>
      YosysLoaderResult(
        success: j['success'] as bool,
        rootChildren: j['rootChildren'] as int?,
        topNodeId: j['topNodeId'] as String?,
        topNodePorts: j['topNodePorts'] as int?,
        error: j['error'] as String?,
        stack: j['stack'] as String?,
      );

  @override
  String toString() => success
      ? 'YosysLoaderResult(success, rootChildren: $rootChildren, '
          'topNodeId: $topNodeId, topNodePorts: $topNodePorts)'
      : 'YosysLoaderResult(failed: $error)';
}

/// JavaScript interop to access JSON.parse.
@JS('JSON.parse')
external JSObject _jsonParse(JSString jsonString);

/// JavaScript interop to access process.cwd().
@JS('process.cwd')
external JSFunction get _jsCwd;

/// Get current working directory.
String _cwd() {
  final result = _jsCwd.callAsFunction();
  return (result! as JSString).toDart;
}

/// Static interop types to describe the JS shape returned by d3-yosys.
@JS()
@staticInterop
class YosysResult {}

/// Extensions to access properties of YosysResult.
extension YosysResultExt on YosysResult {
  /// Children nodes.
  external JSArray? get children;
}

/// Static interop types to describe the JS shape returned by d3-yosys.
@JS()
@staticInterop
class YosysNode {}

/// Extensions to access properties of YosysNode.
extension YosysNodeExt on YosysNode {
  /// Node ID.
  external JSString? get id;

  /// Node ports.
  external JSArray? get ports;
}

/// Load the yosys function from d3-yosys module using dynamic import.
/// Returns a Future since dynamic import is async.
Future<JSFunction?> _loadYosysFn() async {
  // Build list of paths to try - using file:// URLs for ES module import
  final paths = <String>[];

  // Try with cwd prefix first (absolute path as file:// URL)
  try {
    final cwd = _cwd();
    paths.add(
        'file://$cwd/lib/src/synthesizers/schematic/yosys/d3-yosys/src/yosys.js');
  } on Object catch (_) {}

  // Also try relative paths
  paths.addAll([
    './lib/src/synthesizers/schematic/yosys/d3-yosys/src/yosys.js',
    '../lib/src/synthesizers/schematic/yosys/d3-yosys/src/yosys.js',
    'lib/src/synthesizers/schematic/yosys/d3-yosys/src/yosys.js',
  ]);

  for (final p in paths) {
    try {
      // Use importModule from dart:js_interop for ES modules
      final promise = importModule(p.toJS);
      final mod = await promise.toDart;
      final fn = mod['yosys'];
      if (fn != null) {
        // Try to use as JSFunction - will throw if not callable
        return fn as JSFunction;
      }
    } on Object catch (_) {
      continue;
    }
  }
  return null;
}

/// JS implementation: call d3-yosys directly in the Node runtime.
Future<YosysLoaderResult> runYosysLoaderFromString(String jsonString) async {
  try {
    // Load the yosys function (async for ES module import)
    final yosysFn = await _loadYosysFn();
    if (yosysFn == null) {
      return YosysLoaderResult(
        success: false,
        error: 'Could not load d3-yosys module. '
            'Tried multiple paths but none worked.',
      );
    }

    // Parse JSON string using JavaScript's JSON.parse
    final jsObj = _jsonParse(jsonString.toJS);

    // Call the yosys function
    final result = yosysFn.callAsFunction(null, jsObj);
    if (result == null) {
      return YosysLoaderResult(
        success: false,
        error: 'yosys function returned null',
      );
    }

    // Convert JS return value to static interop type so we can access
    // the expected properties with typed getters.
    final resultObj = (result as JSObject) as YosysResult;

    var rootChildren = 0;
    String? topNodeId;
    int? topNodePorts;

    final children = resultObj.children;
    if (children != null) {
      final childrenList = children.toDart;
      rootChildren = childrenList.length;

      if (childrenList.isNotEmpty) {
        final topNode = (childrenList[0]! as JSObject) as YosysNode;
        final id = topNode.id;
        if (id != null) {
          topNodeId = id.toDart;
        }
        final ports = topNode.ports;
        if (ports != null) {
          topNodePorts = ports.toDart.length;
        }
      }
    }

    return YosysLoaderResult(
      success: true,
      rootChildren: rootChildren,
      topNodeId: topNodeId,
      topNodePorts: topNodePorts,
    );
  } on Object catch (e, st) {
    return YosysLoaderResult(
      success: false,
      error: 'JS yosys call failed: $e',
      stack: st.toString(),
    );
  }
}

/// JavaScript interop to access Node's require function (for CommonJS modules).
@JS('require')
external JSFunction get _jsRequire;

/// Call require with a path.
JSAny? _require(String path) => _jsRequire.callAsFunction(null, path.toJS);

/// JS implementation: run loader on a file path.
/// In JS we read the file using Node's fs module and call d3-yosys directly.
Future<YosysLoaderResult> runYosysLoader(String jsonPath) async {
  try {
    // Use Node's fs module to read the file
    final fs = _require('fs');
    if (fs == null) {
      return YosysLoaderResult(
        success: false,
        error: 'Could not load Node fs module',
      );
    }

    final fsObj = fs as JSObject;
    final readFileSync = fsObj['readFileSync'] as JSFunction?;
    if (readFileSync == null) {
      return YosysLoaderResult(
        success: false,
        error: 'fs.readFileSync not available',
      );
    }

    final content =
        readFileSync.callAsFunction(fsObj, jsonPath.toJS, 'utf8'.toJS);
    if (content == null) {
      return YosysLoaderResult(
        success: false,
        error: 'Failed to read file: $jsonPath',
      );
    }

    final jsonString = (content as JSString).toDart;
    return runYosysLoaderFromString(jsonString);
  } on Object catch (e, st) {
    return YosysLoaderResult(
      success: false,
      error: 'JS loader failed: $e',
      stack: st.toString(),
    );
  }
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flc_service.dart
// FLC resolution service — resolves signal names to source frames using
// FLC data fetched from the running ROHD application.
//
// 2026 April 27
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:rohd_source_navigator/flc_data.dart';

/// Fetches per-module FLC JSON from the running ROHD app.
typedef FlcModuleFetcher = Future<Map<String, dynamic>?> Function(
    String definitionName);

/// Fetches the full FLC hierarchy JSON from the running ROHD app.
typedef FlcHierarchyFetcher = Future<Map<String, dynamic>?> Function();

/// Fetches the FLC file path from the running ROHD app.
///
/// The path is an absolute filesystem path to the `.flc.json` sidecar
/// written by `FlcService.current?.writtenPath` in the live isolate.
typedef FlcPathFetcher = Future<String?> Function();

/// A resolved source frame ready to be sent to the ROHD VS Code extension.
///
/// Mirrors the `SourceFrame` interface expected by `rohd.openSourceLocations`.
class SourceFrame {
  /// File path (package-relative, e.g. `lib/src/foo.dart`).
  final String file;

  /// 1-based line number.
  final int line;

  /// 1-based column number.
  final int col;

  /// Optional description (e.g. function name from stack trace).
  final String? desc;

  /// Frame type: `'sv'` for SystemVerilog, `'rohd'` for ROHD Dart source.
  final String type;

  /// Creates a [SourceFrame].
  const SourceFrame({
    required this.file,
    required this.line,
    required this.col,
    this.desc,
    this.type = 'rohd',
  });

  /// Serialize to JSON for transmission over DTD.
  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        'col': col,
        if (desc != null) 'desc': desc,
        'type': type,
      };
}

/// Service that resolves signal/instance names to [SourceFrame] lists
/// using FLC data fetched from the running ROHD application via the
/// tree service.
///
/// Caches [FlcData] per module definition name and provides lookup
/// methods that produce frames compatible with the `rohd.openSourceLocations`
/// VS Code command.
class FlcService {
  /// Fetches per-module FLC JSON from the running ROHD app.
  final FlcModuleFetcher _fetchModuleFlc;

  /// Fetches the full FLC hierarchy JSON.
  final FlcHierarchyFetcher _fetchFlcHierarchy;

  /// Optional fetcher for the FLC file path (used for DTD-based lookup).
  final FlcPathFetcher? _fetchFlcFilePath;

  /// Optional callback to clear upstream caches (e.g. TreeService).
  final VoidCallback? _onClearCache;

  /// Parsed FLC data, keyed by module definition name.
  final _cache = <String, FlcData>{};

  /// FLC data parsed from the full hierarchy fetch.
  FlcData? _hierarchyFlc;

  /// Cached FLC file path (returned by the VM after writing to disk).
  String? _cachedFlcPath;

  /// Creates a [FlcService] with the supplied fetchers.
  FlcService({
    required FlcModuleFetcher fetchModuleFlc,
    required FlcHierarchyFetcher fetchFlcHierarchy,
    FlcPathFetcher? fetchFlcFilePath,
    VoidCallback? onClearCache,
  })  : _fetchModuleFlc = fetchModuleFlc,
        _fetchFlcHierarchy = fetchFlcHierarchy,
        _fetchFlcFilePath = fetchFlcFilePath,
        _onClearCache = onClearCache;

  /// Resolve a signal to a list of [SourceFrame]s.
  ///
  /// [moduleName] is the module definition name (e.g. `'AdderModule'`).
  /// [signalName] is the signal name within that module (e.g. `'sum'`).
  ///
  /// Returns an empty list if the signal cannot be resolved.
  Future<List<SourceFrame>> resolveSignal(
    String moduleName,
    String signalName,
  ) async {
    final flcData = await _getFlcData(moduleName);
    if (flcData == null) {
      return [];
    }

    // Try signal lookup first, then instance lookup.
    final entry = flcData.lookupSignalEntry(moduleName, signalName) ??
        flcData.lookupInstanceEntry(moduleName, signalName);
    if (entry == null) {
      debugPrint(
        '[FlcService] No FLC entry for '
        '$moduleName.$signalName',
      );
      debugPrint('[FlcService] Available modules: ${flcData.moduleNames}');
      debugPrint(
        '[FlcService] Signals in $moduleName: '
        '${flcData.signalNamesFor(moduleName)}',
      );
      debugPrint(
        '[FlcService] Instances in $moduleName: '
        '${flcData.instanceNamesFor(moduleName)}',
      );
      return [];
    }

    return _entryToFrames(entry, signalName: signalName);
  }

  /// Resolve multiple signals at once.
  ///
  /// Each signal is a map with `'module'` and `'name'` keys.
  /// Returns all resolved frames concatenated (suitable for multi-frame
  /// navigation in the ROHD VS Code extension).
  Future<List<SourceFrame>> resolveSignals(
    List<Map<String, String>> signals,
  ) async {
    final allFrames = <SourceFrame>[];
    for (final signal in signals) {
      final module = signal['module'] ?? '';
      final name = signal['name'] ?? '';
      if (module.isEmpty || name.isEmpty) {
        continue;
      }
      final frames = await resolveSignal(module, name);
      allFrames.addAll(frames);
    }
    return allFrames;
  }

  /// Parse a signal path (e.g. `"Root/mod1/signalName"`) into a
  /// module + signal name pair and resolve it.
  ///
  /// The module name is the second-to-last segment; the signal name is
  /// the last segment.  This matches the convention used by the schematic
  /// canvas `onGoToSource` callback.
  Future<List<SourceFrame>> resolveSignalPath(String path) async {
    final segments = path.split('/');
    if (segments.length < 2) {
      return [];
    }
    final signalName = segments.last;
    final moduleName = segments[segments.length - 2];
    final frames = await resolveSignal(moduleName, signalName);
    return frames;
  }

  /// Resolve multiple signal paths.
  Future<List<SourceFrame>> resolveSignalPaths(List<String> paths) async {
    final allFrames = <SourceFrame>[];
    for (final path in paths) {
      final frames = await resolveSignalPath(path);
      allFrames.addAll(frames);
    }
    return allFrames;
  }

  /// Return the set of source format identifiers available for [moduleName].
  ///
  /// Scans the FLC data for the module and checks which frame types are
  /// present.  Returns one or more of `'rohd'`, `'sv'`, `'sc'`, etc.
  ///
  /// Returns an empty set when the module is unknown or the FLC data
  /// has not been loaded yet.
  Future<Set<String>> getModuleFormats(String moduleName) async {
    final flcData = await _getFlcData(moduleName);
    if (flcData == null) {
      debugPrint('[FlcService] getModuleFormats($moduleName): flcData is null');
      return const {};
    }

    final signalNames = flcData.signalNamesFor(moduleName);
    final instanceNames = flcData.instanceNamesFor(moduleName);
    debugPrint(
      '[FlcService] getModuleFormats($moduleName): '
      'flcData.moduleNames=${flcData.moduleNames}, '
      'signals=${signalNames.length}, instances=${instanceNames.length}',
    );

    final formats = <String>{};
    for (final signal in signalNames) {
      final entry = flcData.lookupSignalEntry(moduleName, signal);
      if (entry == null) {
        continue;
      }
      if (entry.frames.isNotEmpty) {
        formats.add('rohd');
      }
      for (final outFrame in entry.outputFrames) {
        if (outFrame.type.isNotEmpty) {
          formats.add(outFrame.type);
        }
      }
      // Short-circuit: all three main formats found.
      if (formats.containsAll(['rohd', 'sv', 'sc'])) {
        break;
      }
    }

    // Also check instance entries (sub-modules expose their own frames).
    if (!formats.containsAll(['rohd', 'sv', 'sc'])) {
      for (final inst in instanceNames) {
        final entry = flcData.lookupInstanceEntry(moduleName, inst);
        if (entry == null) {
          continue;
        }
        if (entry.frames.isNotEmpty) {
          formats.add('rohd');
        }
        for (final outFrame in entry.outputFrames) {
          if (outFrame.type.isNotEmpty) {
            formats.add(outFrame.type);
          }
        }
        if (formats.containsAll(['rohd', 'sv', 'sc'])) {
          break;
        }
      }
    }

    debugPrint('[FlcService] getModuleFormats($moduleName): formats=$formats');
    return formats;
  }

  /// Clear all cached FLC data.
  ///
  /// Call on VM disconnect or debug restart.
  void clearCache() {
    _cache.clear();
    _hierarchyFlc = null;
    _cachedFlcPath = null;
    _onClearCache?.call();
    debugPrint('[FlcService] Cache cleared');
  }

  /// Return the FLC file path from the running ROHD app, or `null` if
  /// no FLC path fetcher was provided or the fetch fails.
  ///
  /// The result is cached after the first successful fetch so subsequent
  /// calls are effectively free.
  Future<String?> getFlcPath() async {
    if (_cachedFlcPath != null) {
      return _cachedFlcPath;
    }
    if (_fetchFlcFilePath == null) {
      return null;
    }
    _cachedFlcPath = await _fetchFlcFilePath();
    debugPrint('[FlcService] getFlcPath: $_cachedFlcPath');
    return _cachedFlcPath;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Get parsed FLC data for a module, fetching and caching as needed.
  Future<FlcData?> _getFlcData(String moduleName) async {
    // Check per-module cache.
    if (_cache.containsKey(moduleName)) {
      debugPrint('[FlcService] _getFlcData($moduleName): per-module cache hit');
      return _cache[moduleName];
    }

    // Check hierarchy-level cache (covers all modules at once).
    if (_hierarchyFlc != null &&
        _hierarchyFlc!.moduleNames.contains(moduleName)) {
      debugPrint('[FlcService] _getFlcData($moduleName): hierarchy cache hit');
      return _hierarchyFlc;
    }

    // Fetch per-module FLC from the running app.
    final json = await _fetchModuleFlc(moduleName);
    if (json == null) {
      debugPrint(
        '[FlcService] _getFlcData($moduleName): '
        'per-module fetch returned null, trying hierarchy',
      );
      // Try hierarchy-level fetch as fallback.
      final hierarchy = await _fetchAndCacheHierarchy(moduleName);
      return hierarchy;
    }

    // Detect error responses from the running app (e.g.
    // {"status": "unavailable", "reason": "trace service not registered"}).
    if (json.containsKey('status') && json['status'] != 'ok') {
      debugPrint(
        '[FlcService] _getFlcData($moduleName): '
        'error response: ${json['status']} — ${json['reason'] ?? ''}',
      );
      // Fall through to hierarchy fetch.
      final hierarchy = await _fetchAndCacheHierarchy(moduleName);
      return hierarchy;
    }

    final rawStr = json.toString();
    final rawPreview = rawStr.substring(0, rawStr.length.clamp(0, 300));
    debugPrint(
      '[FlcService] _getFlcData($moduleName): '
      'raw JSON keys=${json.keys.toList()}, '
      'raw=$rawPreview',
    );

    // Parse and cache.  The per-module JSON from TraceService uses the
    // trie-based v5 format.
    final flcData = FlcData.fromJson(json);
    debugPrint(
      '[FlcService] _getFlcData($moduleName): '
      'fetched & parsed, modules=${flcData.moduleNames}',
    );
    _cache[moduleName] = flcData;
    return flcData;
  }

  /// Fetch the full FLC hierarchy and cache it.
  Future<FlcData?> _fetchAndCacheHierarchy(String moduleName) async {
    if (_hierarchyFlc != null) {
      return _hierarchyFlc;
    }

    final json = await _fetchFlcHierarchy();
    if (json == null) {
      return null;
    }

    return _hierarchyFlc = FlcData.fromJson(json);
  }

  /// Convert an [FlcEntry] to a list of [SourceFrame]s.
  ///
  /// FLC traces are stored innermost → outermost, but the VS Code extension
  /// navigates to frame[0] first.  Reverse the ROHD frames so the outermost
  /// (user-facing) call site appears first, with deeper implementation
  /// frames available via Next/Prev cycling.
  ///
  /// When [signalName] is provided it is stored in [SourceFrame.desc] so
  /// downstream consumers (e.g. the source-frame picker) can derive a
  /// highlight prefix for the target line.
  List<SourceFrame> _entryToFrames(FlcEntry entry, {String? signalName}) {
    final frames = <SourceFrame>[];

    // Add ROHD source frames in outermost-first order.
    for (final f in entry.frames.reversed) {
      frames.add(
        SourceFrame(
          file: f.file,
          line: f.line,
          col: f.column,
          desc: signalName,
          type: f.type,
        ),
      );
    }

    // Add output-language frames (SV, SC, etc.) if present.
    for (final of in entry.outputFrames) {
      frames.add(
        SourceFrame(
          file: of.file,
          line: of.line,
          col: of.column,
          desc: signalName,
          type: of.type,
        ),
      );
    }

    return frames;
  }
}

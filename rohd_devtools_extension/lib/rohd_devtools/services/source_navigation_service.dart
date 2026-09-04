// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// source_navigation_service.dart
// Service for sending cross-probe source navigation requests from the
// DevTools extension to the ROHD VS Code extension via DTD.
//
// Resolves signals to SourceFrames via the ROHD extension's DTD
// `rohd.lookupSignal` service, then sends frames to `rohd.goToSource`.
//
// 2026 April 27
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdSourceFormat;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Callback signature for fetching a source line from a file.
///
/// [fileUri] is the package-relative path (e.g. `lib/src/counter.dart`).
/// [line] is the 1-based line number.
/// Returns the source line text, or `null` if unavailable.
typedef SourceLineFetcher = Future<String?> Function(String fileUri, int line);

/// A [SourceFrame] enriched with enclosing method/class names resolved
/// by the ROHD VS Code extension via the Dart language server.
class EnrichedFrame {
  /// The underlying source frame.
  final SourceFrame frame;

  /// Enclosing method/function name (e.g. `"build"`).
  final String? methodName;

  /// Enclosing class name (e.g. `"Serializer"`).
  final String? className;

  /// Human-readable label for UI display.
  final String label;

  /// Creates an [EnrichedFrame].
  const EnrichedFrame({
    required this.frame,
    required this.label,
    this.methodName,
    this.className,
  });

  /// Decode an [EnrichedFrame] from a JSON map produced by the
  /// ROHD VS Code extension or compatible tooling.
  factory EnrichedFrame.fromJson(Map<String, dynamic> json) => EnrichedFrame(
        frame: SourceFrame(
          file: json['file'] as String? ?? '',
          line: json['line'] as int? ?? 0,
          col: json['col'] as int? ?? 0,
          desc: json['desc'] as String?,
          type: json['type'] as String? ?? 'rohd',
        ),
        methodName: json['methodName'] as String?,
        className: json['className'] as String?,
        label: json['label'] as String? ?? '${json['file']}:${json['line']}',
      );

  /// Text prefix to highlight on the target source line.
  ///
  /// Extraction priority:
  /// 1. Method name (per-frame, most differentiating across the stack).
  /// 2. Class name (if method is absent but class is available).
  /// 3. SignalOccurrence name (`frame.desc`) — same for all frames in a trace,
  ///    so used only as a last resort.
  /// 4. Label truncated at the first interesting separator (`.` or `(`).
  String? get highlight {
    // Method/class name from enrichment — unique per frame.
    if (methodName != null && methodName!.isNotEmpty) {
      return methodName;
    }
    if (className != null && className!.isNotEmpty) {
      return className;
    }

    // SignalOccurrence name from FLC (same for every frame in a stack trace).
    final desc = frame.desc;
    if (desc != null && desc.isNotEmpty) {
      return desc;
    }

    // Truncate label at first interesting separator.
    for (final sep in ['.', '(']) {
      final idx = label.indexOf(sep);
      if (idx > 0) {
        return label.substring(0, idx);
      }
    }

    return null;
  }
}

/// Service that orchestrates cross-probe source navigation:
///
/// 1. Resolves signal paths → [SourceFrame] lists via DTD `rohd.lookupSignal`
///    or, when DTD is unavailable, via a local [FlcService] (loopback mode)
/// 2. Sends frames to `rohd.goToSource` DTD service (registered by
///    the ROHD VS Code extension) when DTD is available
///
/// Handles DTD unavailability gracefully — lookup still works via
/// [FlcService] so the picker UI can display resolved frames even
/// when no VS Code editor is reachable.
class SourceNavigationService {
  /// The DTD connection, supplied externally (shared with standalone shell
  /// or obtained from dtdManager in extension mode).
  DartToolingDaemon? _dtd;

  /// Local FLC service for in-process lookup (loopback mode).
  /// Used as a fallback when DTD is unavailable.
  FlcService? _flcService;

  /// Optional hierarchy for translating instance paths → definition paths.
  HierarchyService? _hierarchy;

  /// Optional callback for fetching source lines from the running app.
  /// When set, enriched frames include a source-line prefix for highlighting.
  SourceLineFetcher? sourceLineFetcher;

  /// Creates a [SourceNavigationService] with no DTD or FLC bound.
  SourceNavigationService();

  /// Clear the source line fetcher.  Call on VM disconnect.
  void clearSourceLineFetcher() {
    sourceLineFetcher = null;
  }

  /// Set the DTD connection.  Call when DTD becomes available.
  void setDtd(DartToolingDaemon dtd) {
    _dtd = dtd;
    debugPrint('[SourceNav] DTD connection set');
  }

  /// Clear the DTD connection.  Call on DTD disconnect.
  void clearDtd() {
    _dtd = null;
    debugPrint('[SourceNav] DTD connection cleared');
  }

  /// Set the local FLC service (loopback / in-process fallback).
  void setFlcService(FlcService flcService) {
    _flcService = flcService;
    debugPrint('[SourceNav] FlcService set (local fallback)');
  }

  /// Clear the local FLC service.
  void clearFlcService() {
    _flcService?.clearCache();
    _flcService = null;
    debugPrint('[SourceNav] FlcService cleared');
  }

  /// Set the hierarchy service for instance→definition path translation.
  void setHierarchy(HierarchyService hierarchy) {
    _hierarchy = hierarchy;
    debugPrint('[SourceNav] Hierarchy set');
  }

  /// Clear the hierarchy.  Call on VM disconnect.
  void clearHierarchy() {
    _hierarchy = null;
  }

  /// Whether DTD is connected.
  bool get _hasDtd => _dtd != null && !_dtd!.isClosed;

  /// Whether signal lookup can be performed (DTD or local FlcService).
  bool get isAvailable => _hasDtd || _flcService != null;

  /// Navigate to source for a list of signal paths.
  ///
  /// SignalOccurrence paths can be either instance paths (`serializer/equalsMax`)
  /// or definition paths (`Serializer_W80_8/equalsMax`).  When a
  /// [HierarchyService] is set, instance paths are translated to
  /// definition paths automatically using [HierarchyOccurrence.definition].
  ///
  /// Returns `true` if navigation succeeded, `false` if DTD is
  /// unavailable or no frames could be resolved.
  Future<bool> goToSourceFromPaths(List<String> signalPaths) async {
    if (!isAvailable) {
      debugPrint('[SourceNav] Neither DTD nor FlcService available');
      return false;
    }

    // Translate instance paths → definition paths if hierarchy is available,
    // but retain the original instance path as a fallback candidate.  Some
    // FLC payloads are keyed by generated instance/module names even when the
    // hierarchy can report a richer definition name.
    final pathCandidates = signalPaths.map(_candidateLookupPaths).toList();
    final paths = pathCandidates.map((candidates) => candidates.first).toList();
    debugPrint(
      '[SourceNav] goToSourceFromPaths: '
      'hierarchy=${_hierarchy != null}, '
      'input=$signalPaths, translated=$paths, candidates=$pathCandidates',
    );

    // Resolve frames — DTD first, FlcService fallback.
    final frames = await _lookupSignalsForPathCandidates(pathCandidates);
    if (frames.isEmpty) {
      debugPrint('[SourceNav] No frames resolved for: $paths');
      return false;
    }

    final navigated = await _sendGoToSource(frames);
    return navigated;
  }

  /// Translate an instance-based path to a definition-based path.
  ///
  /// Given `serializer/equalsMax`, walks the hierarchy to find the
  /// `serializer` node, reads its `.definition` (`Serializer_W80_8`), and
  /// returns `Serializer_W80_8/equalsMax`.
  ///
  /// Returns the original path unchanged when:
  /// - No hierarchy is set
  /// - The path has fewer than 2 segments
  /// - The parent node isn't found or has no `.definition`
  String _instanceToDefPath(String path) {
    if (_hierarchy == null) {
      return path;
    }

    final segments = path.split('/');
    if (segments.length < 2) {
      return path;
    }

    // The parent module is everything except the last segment (signal name).
    final modulePath = segments.sublist(0, segments.length - 1).join('/');
    final signalName = segments.last;

    final node = _hierarchy!.occurrenceByPathname(modulePath);
    final owner = _nearestLookupOwner(node, signalName);
    debugPrint(
      '[SourceNav] _instanceToDefPath: '
      'modulePath=$modulePath, node=${node?.name}, '
      'type=${node?.definition}, owner=${owner?.path()}, '
      'ownerType=${owner?.definition}, signal=$signalName',
    );
    if (owner == null || owner.definition == null) {
      return path;
    }

    final defPath = '${owner.definition}/$signalName';
    if (defPath != path) {
      debugPrint('[SourceNav] Translated: $path → $defPath');
    }
    return defPath;
  }

  List<String> _candidateLookupPaths(String path) {
    final translated = _instanceToDefPath(path);
    if (translated == path) {
      return [path];
    }
    return [translated, path];
  }

  HierarchyOccurrence? _nearestLookupOwner(
    HierarchyOccurrence? node,
    String name,
  ) {
    var current = node;
    while (current != null) {
      if (current.signalIndexByName(name) >= 0 ||
          current.childIndexByName(name) >= 0) {
        return current;
      }
      current = current.parent;
    }
    return node;
  }

  /// Navigate to source for a list of module+signal name pairs.
  ///
  /// Each entry should have `'module'` and `'name'` keys.
  Future<bool> goToSourceFromSignals(List<Map<String, String>> signals) async {
    if (!isAvailable) {
      debugPrint('[SourceNav] Neither DTD nor FlcService available');
      return false;
    }

    // Convert to paths for lookup.
    final paths = signals
        .map((s) => '${s['module'] ?? ''}/${s['name'] ?? ''}')
        .where((p) => p.length > 1)
        .toList();

    final frames = await _lookupSignals(paths);
    if (frames.isEmpty) {
      debugPrint('[SourceNav] No frames resolved for: $signals');
      return false;
    }

    final navigated = await _sendGoToSource(frames);
    return navigated;
  }

  // -------------------------------------------------------------------------
  // SignalOccurrence lookup: DTD → FlcService fallback
  // -------------------------------------------------------------------------

  /// Resolve signal paths to [SourceFrame]s.
  ///
  /// Prefers DTD `rohd.lookupSignal` when DTD is available, passing the FLC
  /// file path obtained from the running ROHD app via [FlcService.getFlcPath].
  /// Falls back to the local [FlcService] (in-process lookup) when DTD is
  /// unavailable.
  Future<List<SourceFrame>> _lookupSignals(
    List<String> paths, {
    RohdSourceFormat? format,
  }) async {
    if (_hasDtd) {
      final frames = await _lookupSignalsViaDtd(paths, format: format);
      if (frames.isNotEmpty) {
        return frames;
      }
      if (_flcService != null) {
        debugPrint(
          '[SourceNav] DTD lookup returned no frames; '
          'falling back to FlcService',
        );
        final frames = await _lookupSignalsViaFlcService(
          paths,
          format: format,
        );
        return frames;
      }
      return const [];
    }
    if (_flcService != null) {
      final frames = await _lookupSignalsViaFlcService(
        paths,
        format: format,
      );
      return frames;
    }
    return const [];
  }

  Future<List<SourceFrame>> _lookupSignalsForPathCandidates(
    List<List<String>> pathCandidates, {
    RohdSourceFormat? format,
  }) async {
    final allFrames = <SourceFrame>[];
    for (final candidates in pathCandidates) {
      for (final path in candidates) {
        final frames = await _lookupSignals([path], format: format);
        if (frames.isNotEmpty) {
          allFrames.addAll(frames);
          break;
        }
      }
    }
    return allFrames;
  }

  /// Resolve via local [FlcService] (in-process / loopback fallback).
  Future<List<SourceFrame>> _lookupSignalsViaFlcService(
    List<String> paths, {
    RohdSourceFormat? format,
  }) async {
    final allFrames = <SourceFrame>[];
    for (final path in paths) {
      final lookup = _splitLookupPath(path);
      if (lookup == null) {
        continue;
      }
      final frames = await _flcService!.resolveSignal(
        lookup.moduleName,
        lookup.signalName,
      );
      allFrames.addAll(
        format == null
            ? frames
            : frames.where((frame) => frame.type == format.name),
      );
    }
    debugPrint(
      '[SourceNav] FlcService lookup: '
      '${paths.length} path(s) → ${allFrames.length} frame(s)',
    );
    return allFrames;
  }

  /// Resolve via DTD `rohd.lookupSignal` (ROHD extension has the FLC).
  ///

  ({String moduleName, String signalName})? _splitLookupPath(String path) {
    final segments = path.split('/');
    if (segments.length < 2) {
      return null;
    }
    return (
      moduleName: segments[segments.length - 2],
      signalName: segments.last,
    );
  }

  /// Each path is `"ModuleName/signalName"`.  The `flcPath` (absolute path to
  /// the `.flc.json` file on disk) is fetched once from the running ROHD app
  /// via [FlcService.getFlcPath] and cached for the session.
  Future<List<SourceFrame>> _lookupSignalsViaDtd(
    List<String> paths, {
    RohdSourceFormat? format,
  }) async {
    // Obtain the FLC file path from the running app (tiny string, cached).
    final flcPath = await _flcService?.getFlcPath();
    if (flcPath == null || flcPath.isEmpty) {
      debugPrint('[SourceNav] DTD lookup skipped: flcPath unavailable');
      return const [];
    }
    final allFrames = <SourceFrame>[];
    for (final path in paths) {
      final lookup = _splitLookupPath(path);
      if (lookup == null) {
        continue;
      }
      final signalName = lookup.signalName;
      final moduleName = lookup.moduleName;

      final frames = await _lookupSignalViaDtd(
        flcPath: flcPath,
        moduleName: moduleName,
        signalName: signalName,
        format: format,
      );
      if (frames.isNotEmpty) {
        allFrames.addAll(frames);
        continue;
      }

      // Per-definition FLC sidecars may be keyed by the generated master
      // definition while schematic paths use instance names.  If the exact
      // module filter misses, search the current FLC file for the signal.
      final unscopedFrames = await _lookupSignalViaDtd(
        flcPath: flcPath,
        moduleName: null,
        signalName: signalName,
        format: format,
      );
      allFrames.addAll(unscopedFrames);
    }
    return allFrames;
  }

  Future<List<SourceFrame>> _lookupSignalViaDtd({
    required String flcPath,
    required String? moduleName,
    required String signalName,
    RohdSourceFormat? format,
  }) async {
    final frames = <SourceFrame>[];

    try {
      final response = await _dtd!.call(
        'rohd',
        'lookupSignal',
        params: {
          'signal': signalName,
          if (moduleName != null) 'module': moduleName,
          'flcPath': flcPath,
          if (format != null) 'format': format.name,
        },
      );

      final result = response.result;
      final status = result['status'] as String?;
      if (status == 'ok' || status == 'partial') {
        final framesList = result['frames'] as List<dynamic>? ?? [];
        // Reverse to outermost-first order (the ROHD extension returns
        // innermost-first, matching raw stack-trace order).
        for (final f in framesList.reversed) {
          final map = f as Map<String, dynamic>;
          frames.add(
            SourceFrame(
              file: map['file'] as String? ?? '',
              line: map['line'] as int? ?? 0,
              col: map['col'] as int? ?? 0,
              desc: map['desc'] as String?,
              type: map['type'] as String? ?? 'rohd',
            ),
          );
        }
        debugPrint(
          '[SourceNav] DTD lookupSignal('
          '${moduleName ?? '<any>'}/$signalName): '
          '${framesList.length} frame(s)',
        );
      } else {
        debugPrint(
          '[SourceNav] DTD lookupSignal('
          '${moduleName ?? '<any>'}/$signalName): '
          '$status — ${result['message'] ?? ''}',
        );
      }
    } on DartToolingDaemonConnectionException catch (e) {
      // The ROHD extension may omit the DTD 'type' field in its response.
      // When the data is otherwise valid, parse frames from the error's
      // embedded JSON rather than discarding a successful lookup.
      if (e.errorCode ==
          DartToolingDaemonConnectionException.callParamsMissingTypeError) {
        final parsed = _extractFramesFromMissingTypeError(e);
        if (parsed.isNotEmpty) {
          // Reverse to outermost-first (same as the normal path).
          frames.addAll(parsed.reversed);
          debugPrint(
            '[SourceNav] DTD lookupSignal('
            '${moduleName ?? '<any>'}/$signalName): '
            '${parsed.length} frame(s) (missing-type workaround)',
          );
          return frames;
        }
      }
      debugPrint(
        '[SourceNav] DTD lookupSignal failed for '
        '${moduleName ?? '<any>'}/$signalName: $e',
      );
    } on Exception catch (e) {
      debugPrint(
        '[SourceNav] DTD lookupSignal error for '
        '${moduleName ?? '<any>'}/$signalName: $e',
      );
    }
    return frames;
  }

  /// Extract [SourceFrame]s from a [DartToolingDaemonConnectionException]
  /// thrown because the response lacked a `type` field but otherwise
  /// contained valid frame data.
  ///
  /// The error message embeds the raw JSON:
  /// `"... Got: {status: ok, frames: [...]}"`.
  /// We parse the `frames` list out of the response map when possible.
  List<SourceFrame> _extractFramesFromMissingTypeError(
    DartToolingDaemonConnectionException e,
  ) {
    try {
      // The exception message format is:
      //   "call received an invalid response, it is missing the 'type' param.
      //    Got: {status: ok, frames: [...]}"
      // The "Got:" payload is a Dart Map.toString() output, which is not valid
      // JSON.  Instead, we look for 'frames' in the message and try a
      // RegExp-based extraction.
      //
      // However, the DTD client actually stores the raw parsed JSON map
      // inside the error.  We cannot access it directly from the exception
      // message alone, so as a best-effort we extract frame maps using a
      // simple pattern.
      final msg = e.message;
      final framesMatch = regExpFirstMatch(
        r'frames:\s*\[(.+)\]',
        msg,
        dotAll: true,
      );
      if (framesMatch == null) {
        return [];
      }

      // The innermost 'frames' list: find all {file: ..., line: ...} entries.
      const framePattern = r'\{file:\s*([^,]+),\s*line:\s*(\d+),\s*col:\s*(\d+)'
          r'(?:,\s*desc:\s*([^,\}]+))?'
          r'(?:,\s*type:\s*([^,\}]+))?\}';
      final frames = <SourceFrame>[];
      for (final m in regExpAllMatches(framePattern, framesMatch.group(1)!)) {
        frames.add(
          SourceFrame(
            file: m.group(1)!.trim(),
            line: int.tryParse(m.group(2)!) ?? 0,
            col: int.tryParse(m.group(3)!) ?? 0,
            desc: m.group(4)?.trim(),
            type: m.group(5)?.trim() ?? 'rohd',
          ),
        );
      }
      return frames;
    } on Exception {
      return [];
    }
  }

  /// Send resolved frames to the ROHD VS Code extension via DTD.
  ///
  /// [method] defaults to `'goToSource'`.
  ///
  /// The client performs type filtering before calling this method.
  ///
  /// Returns `false` (without error) when DTD is unavailable — the frames
  /// are still resolved and can be used by the picker UI.
  Future<bool> _sendGoToSource(
    List<SourceFrame> frames, {
    int index = 0,
    String? highlight,
    String method = 'goToSource',
  }) async {
    if (!_hasDtd) {
      debugPrint(
        '[SourceNav] No DTD — cannot send $method '
        '(${frames.length} frames resolved but no editor reachable)',
      );
      return false;
    }
    try {
      final response = await _dtd!.call(
        'rohd',
        method,
        params: {
          'frames': frames.map((f) => f.toJson()).toList(),
          'index': index,
          if (highlight != null) 'highlight': highlight,
        },
      );

      final result = response.result;
      final status = result['status'];
      if (status == 'ok') {
        debugPrint(
          '[SourceNav] Navigation successful '
          '(${frames.length} frames, index=$index)',
        );
        return true;
      } else {
        debugPrint('[SourceNav] Navigation response: $result');
        if (method != 'goToSource') {
          debugPrint(
            '[SourceNav] Falling back to goToSource '
            '(unsupported method: $method)',
          );
          final navigated = await _sendGoToSource(
            frames,
            index: index,
            highlight: highlight,
          );
          return navigated;
        }
        return false;
      }
    } on DartToolingDaemonConnectionException catch (e) {
      // The ROHD VS Code extension processes the request (editors open)
      // but its response omits the DTD 'type' field, causing the DTD
      // client to throw.  Treat missing-type as success.
      if (e.errorCode ==
          DartToolingDaemonConnectionException.callParamsMissingTypeError) {
        debugPrint(
          '[SourceNav] Navigation sent '
          '(${frames.length} frames, index=$index)',
        );
        return true;
      }
      if (method != 'goToSource') {
        debugPrint(
          '[SourceNav] Falling back to goToSource after DTD error '
          'for $method: $e',
        );
        final navigated = await _sendGoToSource(
          frames,
          index: index,
          highlight: highlight,
        );
        return navigated;
      }
      debugPrint('[SourceNav] Failed to send goToSource: $e');
      return false;
    } on Exception catch (e) {
      if (method != 'goToSource') {
        debugPrint(
          '[SourceNav] Falling back to goToSource after error '
          'for $method: $e',
        );
        final navigated = await _sendGoToSource(
          frames,
          index: index,
          highlight: highlight,
        );
        return navigated;
      }
      debugPrint('[SourceNav] Failed to send goToSource: $e');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Two-step resolve → pick → navigate API
  // -------------------------------------------------------------------------

  /// Resolve signal paths to enriched frames with method/class names.
  ///
  /// Step 1 of the two-step flow:
  /// 1. Resolve frames via DTD or local FlcService
  /// 2. Optionally filter to [format]
  /// 3. Enrich with source line prefix for highlighting
  /// 4. Return enriched frames for UI display in a picker
  ///
  /// Returns an empty list if neither DTD nor FlcService is available.
  Future<List<EnrichedFrame>> resolveSourceFrames(
    List<String> signalPaths, {
    RohdSourceFormat? format,
  }) async {
    if (!isAvailable) {
      debugPrint('[SourceNav] Neither DTD nor FlcService available');
      return [];
    }

    final pathCandidates = signalPaths.map(_candidateLookupPaths).toList();
    final paths = pathCandidates.map((candidates) => candidates.first).toList();
    debugPrint(
      '[SourceNav] resolveSourceFrames: '
      'input=$signalPaths, translated=$paths, candidates=$pathCandidates',
    );

    final frames = await _lookupSignalsForPathCandidates(
      pathCandidates,
      format: format,
    );
    if (frames.isEmpty) {
      debugPrint('[SourceNav] No FLC frames to resolve for: $paths');
      return [];
    }

    final filteredFrames = format == null
        ? frames
        : frames.where((f) => f.type == format.name).toList();
    if (filteredFrames.isEmpty) {
      final formatName = format?.name ?? 'any';
      debugPrint('[SourceNav] No $formatName frames resolved for: $paths');
      return [];
    }

    final enriched = await _enrichFrames(filteredFrames);
    return enriched;
  }

  /// DTD service method name used to navigate to [format].
  ///
  /// We filter frames by format on the client before sending, then always
  /// call `goToSource`. This avoids silent no-op behavior in older or
  /// inconsistent bridges where format-specific methods can return success
  /// even when no navigation occurs.
  static String _methodForFormat(RohdSourceFormat format) => 'goToSource';

  /// Navigate to a specific enriched frame by index for an arbitrary source
  /// [format] (e.g. ROHD, SV, SystemC).
  ///
  /// This is the generalized entry point used by every viewer's cross-probe
  /// menu; `navigateToRohd`/`navigateToSv` are thin convenience wrappers.
  Future<bool> navigateToFormat(
    List<EnrichedFrame> enrichedFrames,
    int index,
    RohdSourceFormat format,
  ) async {
    if (!isAvailable) {
      return false;
    }
    final frames = enrichedFrames.map((e) => e.frame).toList();
    final highlight = enrichedFrames[index].highlight;
    final navigated = await _sendGoToSource(
      frames,
      index: index,
      highlight: highlight,
      method: _methodForFormat(format),
    );
    return navigated;
  }

  /// Navigate to a specific enriched frame by index (both ROHD + SV).
  Future<bool> navigateToFrame(
    List<EnrichedFrame> enrichedFrames,
    int index,
  ) async {
    if (!isAvailable) {
      return false;
    }
    final frames = enrichedFrames.map((e) => e.frame).toList();
    final highlight = enrichedFrames[index].highlight;
    final navigated = await _sendGoToSource(
      frames,
      index: index,
      highlight: highlight,
    );
    return navigated;
  }

  /// Send frames to `rohd.resolveFrames` and parse enriched results.
  ///
  /// Uses the VM service source line fetcher (when available) to extract
  /// a source-line prefix for each frame.  Falls back to file:line labels
  /// when the fetcher is unavailable.
  Future<List<EnrichedFrame>> _enrichFrames(List<SourceFrame> frames) async {
    final enriched = <EnrichedFrame>[];
    for (final f in frames) {
      final shortFile = f.file.split('/').last;
      String? prefix;
      if (sourceLineFetcher != null) {
        final line = await sourceLineFetcher!(f.file, f.line);
        if (line != null) {
          prefix = _extractPrefix(line, f.col);
          debugPrint(
            '[SourceNav] enrichFrame: ${f.file}:${f.line}:${f.col} '
            '→ prefix="$prefix" (line: "${line.trim()}")',
          );
        } else {
          debugPrint(
            '[SourceNav] enrichFrame: ${f.file}:${f.line} '
            '→ source line not found',
          );
        }
      } else {
        debugPrint('[SourceNav] enrichFrame: no source line fetcher');
      }
      enriched.add(
        EnrichedFrame(
          frame: f,
          label: '$shortFile:${f.line}',
          methodName: prefix,
        ),
      );
    }
    return enriched;
  }

  /// Extract a meaningful prefix from a source line for highlighting.
  ///
  /// Strategy:
  /// - If [col] > 1, use the column to find the symbol starting there and
  ///   include to the end of that identifier token.
  /// - Otherwise, trim the line and take up to the first separator
  ///   (`.`, `(`, `{`, `;`), then trim trailing whitespace.
  /// - Cap at 60 characters to keep the UI compact.
  String? _extractPrefix(String line, int col) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      return null;
    }

    // If column info is valid, start from that position.
    if (col > 1 && col <= line.length) {
      // col is 1-based; convert to 0-based.
      var start = col - 1;
      // Walk BACKWARD to find the true start of the identifier so that a
      // column pointing mid-word (e.g. col=4 in "assign") returns the full
      // word rather than a suffix like "ign".
      while (start > 0 &&
          (_isIdentChar(line.codeUnitAt(start - 1)) ||
              line.codeUnitAt(start - 1) == 0x2E /* . */)) {
        start--;
      }
      // Walk forward to the end of the identifier.
      var end = start;
      while (end < line.length) {
        final ch = line.codeUnitAt(end);
        if (_isIdentChar(ch) || ch == 0x2E /* . */) {
          end++;
        } else {
          break;
        }
      }
      if (end > start) {
        final symbol = line.substring(start, end).trim();
        if (symbol.isNotEmpty) {
          return _cap(symbol);
        }
      }
    }

    // Fallback: take up to the first interesting separator.
    for (final sep in ['.', '(', '{', ';']) {
      final idx = trimmed.indexOf(sep);
      if (idx > 0) {
        return _cap(trimmed.substring(0, idx).trimRight());
      }
    }

    // Last resort: take the whole trimmed line, capped.
    return _cap(trimmed);
  }

  static bool _isIdentChar(int ch) =>
      (ch >= 0x41 && ch <= 0x5A) || // A-Z
      (ch >= 0x61 && ch <= 0x7A) || // a-z
      (ch >= 0x30 && ch <= 0x39) || // 0-9
      ch == 0x5F; // _

  static String _cap(String s) => s.length <= 60 ? s : s.substring(0, 60);
}

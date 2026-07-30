// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flc_data.dart
// FLC (File/Line/Column) data model for cross-probing from schematic
// signals to their ROHD Dart source locations.
//
// Parses trace data embedded in Yosys JSON module attributes under the
// `rohd.src_trace` key, as produced by `SourceTraceRegistry`.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// A single source location frame from an FLC trace.
class FlcFrame {
  /// File path (package-relative, e.g. `lib/src/foo.dart`).
  final String file;

  /// 1-based line number.
  final int line;

  /// 1-based column number.
  final int column;

  /// Frame type: `'rohd'` for ROHD Dart source, `'sv'` for SystemVerilog.
  final String type;

  const FlcFrame({
    required this.file,
    required this.line,
    required this.column,
    this.type = 'rohd',
  });

  @override
  String toString() => '$file:$line:$column [$type]';
}

/// Trace entry for a single signal or instance — one or more stack frames
/// ordered innermost → outermost, plus output-language source locations.
class FlcEntry {
  /// Stack frames for this signal/instance (ROHD Dart source).
  final List<FlcFrame> frames;

  /// Output-language source locations (e.g. SystemVerilog, SystemC).
  ///
  /// Each frame's [FlcFrame.type] identifies the language (`'sv'`, `'sc'`,
  /// etc.).  Multiple frames per language are allowed (e.g. when a signal
  /// appears in both a declaration and an assignment).
  final List<FlcFrame> outputFrames;

  /// Original name before Namer disambiguation (e.g. `sum` before it
  /// became `sum_0`). Null if the name was not renamed.
  final String? origName;

  const FlcEntry({
    required this.frames,
    this.outputFrames = const [],
    this.origName,
  });

  /// First SystemVerilog output frame, or `null` if none.
  ///
  /// Convenience accessor for backward compatibility — equivalent to
  /// `outputFrames.where((f) => f.type == 'sv').firstOrNull`.
  FlcFrame? get svFrame => outputFrames.cast<FlcFrame?>().firstWhere(
        (f) => f!.type == 'sv',
        orElse: () => null,
      );

  /// All frames: output-language frames first, then ROHD src frames.
  List<FlcFrame> get allFrames => [...outputFrames, ...frames];
}

/// FLC data parsed from a v5 trie-based FLC hierarchy JSON file.
class FlcData {
  /// Global file table (index → path).
  final List<String> files;

  /// Module name → signal name → FlcEntry.
  final Map<String, Map<String, FlcEntry>> _signals;

  /// Module name → instance name → FlcEntry.
  final Map<String, Map<String, FlcEntry>> _instances;

  FlcData._({
    required this.files,
    required Map<String, Map<String, FlcEntry>> signals,
    required Map<String, Map<String, FlcEntry>> instances,
  })  : _signals = signals,
        _instances = instances;

  /// Whether any FLC data was found.
  bool get isEmpty => _signals.isEmpty && _instances.isEmpty;

  /// Parse FLC data from a v5/v6 trie-based hierarchy JSON.
  ///
  /// v5 and v6 share the trie structure; v6 adds multi-position support
  /// (comma-separated entries per language) and list-per-language
  /// outputFiles.  Any other version is rejected and returns empty FLC data.
  factory FlcData.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != null && version != 5 && version != 6) {
      return FlcData._(files: [], signals: {}, instances: {});
    }
    final files =
        (json['files'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    final rawModules = json['modules'];
    final modules =
        rawModules is Map ? Map<String, dynamic>.from(rawModules) : null;
    if (modules == null) {
      return FlcData._(files: files, signals: {}, instances: {});
    }

    final signals = <String, Map<String, FlcEntry>>{};
    final instances = <String, Map<String, FlcEntry>>{};

    for (final modEntry in modules.entries) {
      final moduleName = modEntry.key;
      final modMap = modEntry.value as Map<String, dynamic>?;
      if (modMap == null) continue;

      final svFile = modMap['svFile'] as String?;
      // Output files map.
      //   v5: {"sv": "Foo.sv", "sc": "Foo.h"}        (string per language)
      //   v6: {"sv": ["Foo.sv"], "sc": ["Foo.h"]}    (list per language)
      // Falls back to legacy "svFile" field. For lookup we use the first
      // file in each language list (the canonical output).
      final rawOutputFiles = modMap['outputFiles'];
      final outputFiles = <String, String>{
        if (svFile != null) 'sv': svFile,
      };
      if (rawOutputFiles is Map) {
        for (final e in rawOutputFiles.entries) {
          final v = e.value;
          if (v is String) {
            outputFiles[e.key as String] = v;
          } else if (v is List && v.isNotEmpty && v.first is String) {
            outputFiles[e.key as String] = v.first as String;
          }
        }
      }
      final tree = modMap['tree'] as List<dynamic>?;
      if (tree == null) continue;

      final modSignals = <String, FlcEntry>{};
      final modInstances = <String, FlcEntry>{};

      /// Walk a trie node, collecting frames along the path.
      /// Frames are accumulated outermost-first; we reverse at the leaf
      /// to match the innermost-first convention of FlcEntry.frames.
      void walkNode(List<dynamic> node, List<String> path) {
        if (node.isEmpty) return;
        final frame = node[0] as String;
        final currentPath = [...path, frame];

        for (var i = 1; i < node.length; i++) {
          final elem = node[i];
          if (elem is List) {
            // Child trie node.
            walkNode(elem.cast<dynamic>(), currentPath);
          } else if (elem is String) {
            // String-encoded leaf symbol.
            final parsed = _parseSymbolString(elem);
            final name = parsed.name;
            final isInstance = parsed.isInstance;
            final origName = parsed.origName;

            // Build ROHD source frames (reverse to innermost-first).
            final rohdFrames = <FlcFrame>[];
            for (final f in currentPath.reversed) {
              final parts = f.split(':');
              if (parts.length < 2) continue;
              final fi = int.tryParse(parts[0]);
              if (fi == null || fi >= files.length) continue;
              final line = int.tryParse(parts[1]) ?? 1;
              final col = parts.length > 2 ? (int.tryParse(parts[2]) ?? 1) : 1;
              rohdFrames.add(
                FlcFrame(file: files[fi], line: line, column: col),
              );
            }

            // Build output-language frames from parsed positions.
            final outFrames = <FlcFrame>[];
            for (final pos in parsed.outputPositions) {
              final file = outputFiles[pos.type];
              if (file == null) continue;
              outFrames.add(
                FlcFrame(
                  file: file,
                  line: pos.line,
                  column: pos.column,
                  type: pos.type,
                ),
              );
            }

            if (rohdFrames.isNotEmpty || outFrames.isNotEmpty) {
              final entry = FlcEntry(
                frames: rohdFrames,
                outputFrames: outFrames,
                origName: origName,
              );
              if (isInstance) {
                modInstances[name] = entry;
              } else {
                modSignals[name] = entry;
              }
            }
          }
        }
      }

      // tree is a list of root trie nodes.
      for (final rootNode in tree) {
        if (rootNode is List) {
          walkNode(rootNode.cast<dynamic>(), []);
        }
      }

      if (modSignals.isNotEmpty) signals[moduleName] = modSignals;
      if (modInstances.isNotEmpty) instances[moduleName] = modInstances;
    }

    return FlcData._(files: files, signals: signals, instances: instances);
  }

  /// Parse a v5 string-encoded symbol.
  ///
  /// Format: `[*]name[@positions][~origName]`
  ///
  /// Positions are semicolon-separated language groups; within each group
  /// entries are comma-separated.  Each entry is optionally prefixed with a
  /// language tag (only the group's first entry carries the tag):
  ///   - `sv:L:C` — SystemVerilog at line L, column C
  ///   - `sc:L:C` — SystemC at line L, column C
  ///   - `L:C`    — legacy shorthand, treated as `sv:L:C`
  ///
  /// Examples:
  ///   - `clk@2:13`                       (legacy single SV position)
  ///   - `clk@sv:2:13`                    (explicit SV position)
  ///   - `clk@sv:2:13;sc:10:5`            (SV + SystemC)
  ///   - `clk@sv:2:13,5:7;sc:10:5`        (v6: multi-entry within a language)
  static _SymbolInfo _parseSymbolString(String s) {
    final isInstance = s.startsWith('*');
    var rest = isInstance ? s.substring(1) : s;

    String? origName;
    final tildeIdx = rest.indexOf('~');
    if (tildeIdx >= 0) {
      origName = rest.substring(tildeIdx + 1);
      rest = rest.substring(0, tildeIdx);
    }

    final outputPositions = <_OutputPos>[];
    final atIdx = rest.indexOf('@');
    if (atIdx >= 0) {
      final posStr = rest.substring(atIdx + 1);
      rest = rest.substring(0, atIdx);

      for (final group in posStr.split(';')) {
        if (group.isEmpty) continue;
        // A group is `[lang:]entry(,entry)*` where each entry is `[F:]L:C`.
        final entries = group.split(',');
        String? groupLang;
        for (var i = 0; i < entries.length; i++) {
          var part = entries[i];
          if (part.isEmpty) continue;
          // Only the first entry of a group may carry a language tag.
          if (i == 0) {
            final segments = part.split(':');
            final firstIsTag =
                segments.length >= 3 && int.tryParse(segments[0]) == null;
            if (firstIsTag) {
              groupLang = segments[0];
              part = segments.sublist(1).join(':');
            }
          }
          final type = groupLang ?? 'sv';
          final segments = part.split(':');
          final lineStr = segments.length >= 2
              ? segments[segments.length - 2]
              : segments[0];
          final colStr =
              segments.length >= 2 ? segments[segments.length - 1] : null;
          final line = int.tryParse(lineStr) ?? 1;
          final column = colStr != null ? (int.tryParse(colStr) ?? 1) : 1;
          outputPositions
              .add(_OutputPos(type: type, line: line, column: column));
        }
      }
    }

    return _SymbolInfo(
      name: rest,
      isInstance: isInstance,
      outputPositions: outputPositions,
      origName: origName,
    );
  }

  /// Create empty FLC data (no trace information available).
  factory FlcData.empty() => FlcData._(files: [], signals: {}, instances: {});

  /// Look up FLC frames for a signal in a given module.
  ///
  /// Returns null if no trace data exists for this signal.
  /// Falls back to matching by [origName] if the canonical name isn't found.
  List<FlcFrame>? lookupSignal(String moduleName, String signalName) =>
      lookupSignalEntry(moduleName, signalName)?.frames;

  /// Look up the full [FlcEntry] for a signal (includes SV frame if present).
  FlcEntry? lookupSignalEntry(String moduleName, String signalName) {
    final modSignals = _signals[moduleName];
    if (modSignals == null) return null;

    // Direct match.
    final direct = modSignals[signalName];
    if (direct != null) return direct;

    // Fallback: search by origName.
    for (final entry in modSignals.values) {
      if (entry.origName != null && entry.origName == signalName) {
        return entry;
      }
    }
    return null;
  }

  /// Look up FLC frames for an instance (submodule) in a given module.
  List<FlcFrame>? lookupInstance(String moduleName, String instanceName) =>
      lookupInstanceEntry(moduleName, instanceName)?.frames;

  /// Look up the full [FlcEntry] for an instance (includes SV frame if present).
  FlcEntry? lookupInstanceEntry(String moduleName, String instanceName) {
    final modInstances = _instances[moduleName];
    if (modInstances == null) return null;

    final direct = modInstances[instanceName];
    if (direct != null) return direct;

    // Fallback: search by origName.
    for (final entry in modInstances.values) {
      if (entry.origName != null && entry.origName == instanceName) {
        return entry;
      }
    }
    return null;
  }

  /// All module names that have FLC data.
  Set<String> get moduleNames => {..._signals.keys, ..._instances.keys};

  /// Signal names recorded for [moduleName], or empty if none.
  Set<String> signalNamesFor(String moduleName) =>
      _signals[moduleName]?.keys.toSet() ?? <String>{};

  /// Instance names recorded for [moduleName], or empty if none.
  Set<String> instanceNamesFor(String moduleName) =>
      _instances[moduleName]?.keys.toSet() ?? <String>{};

  /// Reverse lookup: find all (moduleName, signalName, entry) tuples whose
  /// ROHD source frames include the given [fileSuffix] and [line].
  ///
  /// [fileSuffix] is matched against the end of each frame's file path
  /// (e.g. `'serializer.dart'` matches `'lib/src/serialization/serializer.dart'`).
  /// When [line] is non-null only frames on that exact line match.
  List<({String module, String signal, FlcEntry entry})> lookupByRohdLine(
    String fileSuffix, {
    int? line,
  }) {
    final results = <({String module, String signal, FlcEntry entry})>[];
    for (final modEntry in _signals.entries) {
      for (final sigEntry in modEntry.value.entries) {
        for (final frame in sigEntry.value.frames) {
          if (frame.file.endsWith(fileSuffix) &&
              (line == null || frame.line == line)) {
            results.add((
              module: modEntry.key,
              signal: sigEntry.key,
              entry: sigEntry.value,
            ));
            break; // one match per signal is enough
          }
        }
      }
    }
    for (final modEntry in _instances.entries) {
      for (final instEntry in modEntry.value.entries) {
        for (final frame in instEntry.value.frames) {
          if (frame.file.endsWith(fileSuffix) &&
              (line == null || frame.line == line)) {
            results.add((
              module: modEntry.key,
              signal: instEntry.key,
              entry: instEntry.value,
            ));
            break;
          }
        }
      }
    }
    return results;
  }
}

/// Parsed v5 symbol string info.
class _SymbolInfo {
  final String name;
  final bool isInstance;
  final List<_OutputPos> outputPositions;
  final String? origName;

  const _SymbolInfo({
    required this.name,
    required this.isInstance,
    this.outputPositions = const [],
    this.origName,
  });
}

/// A parsed output-language position from a symbol string.
class _OutputPos {
  final String type; // e.g. 'sv', 'sc'
  final int line;
  final int column;

  const _OutputPos({required this.type, required this.line, this.column = 1});
}

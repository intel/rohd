// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// source_navigator.dart
// Platform-independent source navigation logic — path normalisation,
// frame cycling, and candidate path generation.
//
// This is the Dart port of the core logic from source_navigator.ts.
// VS Code-specific APIs (editor, decorations, status bar) remain in the
// thin TypeScript shell.
//
// 2026 April 27
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// A single source location frame.
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

  const SourceFrame({
    required this.file,
    required this.line,
    required this.col,
    this.desc,
    this.type = 'rohd',
  });

  /// Create from JSON map (as received over DTD).
  factory SourceFrame.fromJson(Map<String, dynamic> json) => SourceFrame(
        file: json['file'] as String,
        line: json['line'] as int,
        col: json['col'] as int,
        desc: json['desc'] as String?,
        type: (json['type'] as String?) ?? 'rohd',
      );

  /// Serialize to JSON for transmission.
  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        'col': col,
        if (desc != null) 'desc': desc,
        'type': type,
      };

  /// Short display name for status bar.
  String get shortFile => file.split('/').last;

  /// Type tag for display: 'SV', 'ROHD', or 'Source'.
  String get typeTag {
    switch (type) {
      case 'sv':
        return 'SV';
      case 'rohd':
        return 'ROHD';
      default:
        return 'Source';
    }
  }
}

/// Manages frame cycling state for multi-frame source navigation.
class FrameCycler {
  List<SourceFrame> _frames = [];
  int _index = 0;

  /// The current list of frames.
  List<SourceFrame> get frames => _frames;

  /// The current frame index.
  int get index => _index;

  /// Whether there are multiple frames to cycle through.
  bool get hasMultipleFrames => _frames.length > 1;

  /// Whether there are any frames at all.
  bool get isEmpty => _frames.isEmpty;

  /// The current frame, or null if empty.
  SourceFrame? get current => _frames.isEmpty ? null : _frames[_index];

  /// Set frames for a single source location (no cycling).
  void setSingle(SourceFrame frame) {
    _frames = [frame];
    _index = 0;
  }

  /// Set frames for multi-frame navigation.
  void setMultiple(List<SourceFrame> frames, {int startIndex = 0}) {
    _frames = frames;
    _index = startIndex.clamp(0, frames.length - 1);
  }

  /// Advance to the next frame (wrapping).
  SourceFrame? next() {
    if (_frames.isEmpty) return null;
    _index = (_index + 1) % _frames.length;
    return _frames[_index];
  }

  /// Go back to the previous frame (wrapping).
  SourceFrame? prev() {
    if (_frames.isEmpty) return null;
    _index = (_index - 1 + _frames.length) % _frames.length;
    return _frames[_index];
  }

  /// Clear all frames.
  void clear() {
    _frames = [];
    _index = 0;
  }

  /// Status bar text for the current frame.
  ///
  /// Format: `"TYPE 1/3: file.dart:42 desc"`
  String get statusText {
    if (_frames.isEmpty) return '';
    final f = _frames[_index];
    final desc = f.desc != null ? ' ${f.desc}' : '';
    return '${f.typeTag} ${_index + 1}/${_frames.length}: '
        '${f.shortFile}:${f.line}$desc';
  }

  /// Returns the first frame of each unique type (for opening
  /// both ROHD and SV files simultaneously).
  List<SourceFrame> firstOfEachType() {
    final seen = <String>{};
    final result = <SourceFrame>[];
    for (final f in _frames) {
      if (seen.add(f.type)) {
        result.add(f);
      }
    }
    return result;
  }
}

/// Normalize a file path by collapsing `.` and `..` segments.
///
/// FLC paths from SourceTraceRegistry often contain `.dart_tool/../lib/...`
/// which needs collapsing before resolution.
String normalizePath(String filePath) {
  final isAbsolute = filePath.startsWith('/');
  final parts = filePath.split('/');
  final resolved = <String>[];
  for (final part in parts) {
    if (part == '.' || part.isEmpty) {
      continue;
    } else if (part == '..' && resolved.isNotEmpty && resolved.last != '..') {
      resolved.removeLast();
    } else {
      resolved.add(part);
    }
  }
  final joined = resolved.join('/');
  return isAbsolute ? '/$joined' : joined;
}

/// Generate candidate paths for a package-relative file path.
///
/// Given a list of workspace root paths, produces candidates (in order):
/// 1. Normalized path relative to each workspace root
/// 2. Normalized path relative to parent directories (up to [parentLevels])
/// 3. Absolute path (if applicable)
/// 4. Original un-normalized path (fallback)
///
/// Returns relative candidate strings; the caller (TS shell) converts
/// them to URIs.
List<String> resolveCandidatePaths(
  String filePath, {
  List<String> workspaceRoots = const [],
  int parentLevels = 4,
}) {
  final normalized = normalizePath(filePath);
  final candidates = <String>[];

  for (final root in workspaceRoots) {
    // Direct: workspace root + normalized path
    candidates.add('$root/$normalized');

    // Walk up parent directories.
    var parent = root;
    for (var i = 0; i < parentLevels; i++) {
      final lastSlash = parent.lastIndexOf('/');
      if (lastSlash <= 0) break;
      parent = parent.substring(0, lastSlash);
      candidates.add('$parent/$normalized');
    }
  }

  // Absolute path fallback.
  if (normalized.startsWith('/')) {
    candidates.add(normalized);
  }

  // Try original un-normalized path if it differs.
  if (normalized != filePath) {
    for (final root in workspaceRoots) {
      candidates.add('$root/$filePath');
    }
  }

  return candidates;
}

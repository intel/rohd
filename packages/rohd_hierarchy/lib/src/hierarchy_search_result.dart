// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_search_result.dart
// Base class for hierarchy search results.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';

/// Base class for hierarchy search results.
///
/// Holds the common fields shared by signal and occurrence search
/// results: a canonical ID string, pre-split path segments, and display
/// helpers that strip the top-level module name.
@immutable
abstract class HierarchySearchResult {
  /// The full hierarchical path that was found.
  /// Example: `"Top/counter/clk"` or `"Top/CPU/ALU"`.
  final String id;

  /// The hierarchical path segments.
  /// Example: `["Top", "counter", "clk"]`.
  final List<String> path;

  /// Creates a hierarchy search result.
  const HierarchySearchResult({required this.id, required this.path});

  /// The leaf name (last path segment).
  String get name => path.isNotEmpty ? path.last : id;

  // ───────────────────── Display helpers ─────────────────────

  /// Display path with the top-level module name stripped.
  ///
  /// For `Top/counter/clk` this returns `counter/clk`.
  /// For a single-segment path returns the original [id].
  String get displayPath => displaySegments.join('/');

  /// Path segments with the top-level module name stripped.
  ///
  /// For `["Top", "counter", "clk"]` returns `["counter", "clk"]`.
  List<String> get displaySegments => path.length > 1 ? path.sublist(1) : path;

  /// Normalize a user query for hierarchy search.
  ///
  /// Converts common separators (`.`) to the canonical `/` separator.
  static String normalizeQuery(String query) => query.replaceAll('.', '/');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HierarchySearchResult &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

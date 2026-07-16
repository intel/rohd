// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_query.dart
// Pluggable search query abstraction for hierarchy search.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/hierarchy_occurrence.dart';
import 'package:rohd_hierarchy/src/hierarchy_service.dart';
import 'package:rohd_hierarchy/src/prefix_query.dart';
import 'package:rohd_hierarchy/src/regex_query.dart';

// Re-export so callers importing hierarchy_query.dart get the concrete types.
export 'package:rohd_hierarchy/src/prefix_query.dart';
export 'package:rohd_hierarchy/src/regex_query.dart';

/// What kind of hierarchy elements a query should match.
enum SearchTarget {
  /// Match only [HierarchyOccurrence] nodes (modules, instances).
  occurrences,

  /// Match only signals within occurrences.
  signals,

  /// Match both occurrences and signals.
  both,
}

/// Abstract base class for hierarchy search queries.
///
/// A [HierarchyQuery] encapsulates the *matching strategy* (how names are
/// compared) independently of the *tree traversal* (which is always
/// performed by [HierarchyService]).
///
/// ## Contract with [HierarchyService]
///
/// The service walks the [HierarchyOccurrence] tree depth-first.
/// At each node it calls:
///
/// 1. [matchOccurrence] — does this occurrence name satisfy the query at the
///    current match state?  Returns a set of successor states (empty =
///    prune this branch).
/// 2. [matchSignal] — does this signal name satisfy the query at the
///    current match state?
/// 3. [isComplete] — have all parts of the query been consumed at the
///    given state?
///
/// "Match state" is an opaque integer that the query owns.  It typically
/// tracks how many segments/tokens of the query have been consumed so far.
/// The initial state is always `0`.
///
/// ## Crossing hierarchy boundaries
///
/// If [crossesBoundaries] is true the service will, at each depth,
/// additionally try advancing with the *current* state even when the
/// occurrence doesn't match — allowing matches to span across
/// intermediate hierarchy levels (like `**` in glob patterns).
///
/// ## Subclassing
///
/// Implement a concrete query by overriding at least [matchOccurrence],
/// [matchSignal], [isComplete], and [segmentCount].
///
/// The factory [HierarchyQuery.prefix] creates the default
/// prefix-substring query.  [HierarchyQuery.regex] creates a
/// regex/glob query.
///
/// ```dart
/// // Custom fuzzy query
/// class FuzzyQuery extends HierarchyQuery {
///   FuzzyQuery(String rawQuery)
///       : super(rawQuery, target: SearchTarget.signals);
///   ...
/// }
/// ```
abstract class HierarchyQuery {
  /// The original user-supplied query string.
  final String rawQuery;

  /// What this query matches — occurrences, signals, or both.
  final SearchTarget target;

  /// Whether this query can match across hierarchy boundaries.
  ///
  /// When true, the tree walker will try the current match state at
  /// deeper levels even when intermediate occurrences don't match.
  /// Conceptually equivalent to an implicit `**` between segments.
  final bool crossesBoundaries;

  /// Creates a query from [rawQuery].
  ///
  /// Subclasses should parse/compile the query in their constructor.
  const HierarchyQuery(
    this.rawQuery, {
    this.target = SearchTarget.signals,
    this.crossesBoundaries = false,
  });

  /// Number of logical segments in the parsed query.
  ///
  /// Used by the tree walker to know when the query is fully consumed.
  int get segmentCount;

  /// Whether the query is empty / trivial (should return no results).
  bool get isEmpty => rawQuery.trim().isEmpty;

  /// Try matching an occurrence name at match state [stateIndex].
  ///
  /// Returns a set of successor states.  Multiple successors arise when
  /// the query is ambiguous at this point (e.g. a glob-star `**` can
  /// consume zero or more levels).
  ///
  /// An empty set means "no match — prune this subtree".
  Set<int> matchOccurrence(String occurrenceName, int stateIndex);

  /// Whether [signalName] matches the query at state [stateIndex].
  ///
  /// Only called when [target] includes signals.
  bool matchSignal(String signalName, int stateIndex);

  /// Whether the query is fully consumed at [stateIndex].
  ///
  /// Returns true when all segments have been matched and the current
  /// tree position is a valid result.
  bool isComplete(int stateIndex);

  // ──────────────── Built-in query factories ────────────────

  /// Create a **prefix-substring** query.
  ///
  /// The query is split on `/` or `.` into segments.  Each segment is
  /// matched via `startsWith` (for signals) or
  /// `contains` (for occurrences) against names at successive depths.
  factory HierarchyQuery.prefix(
    String rawQuery, {
    SearchTarget target,
  }) = PrefixQuery;

  /// Create a **regex/glob** query.
  ///
  /// Segments are separated by `/`.  Each segment is compiled as a
  /// case-sensitive regex anchored to the full name.  The special
  /// segment `**` matches zero or more hierarchy levels.
  ///
  /// Glob wildcards `*` and `?` are auto-converted to regex equivalents.
  factory HierarchyQuery.regex(
    String rawQuery, {
    SearchTarget target,
  }) = RegexQuery;
}

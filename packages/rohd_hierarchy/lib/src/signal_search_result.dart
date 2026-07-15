// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_search_result.dart
// Result of a signal search with enriched metadata.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';

import 'package:rohd_hierarchy/src/hierarchy_search_result.dart';
import 'package:rohd_hierarchy/src/signal_occurrence.dart';

/// Result of a signal search with enriched metadata.
///
/// Contains the signal's full path, parsed path segments, and the full
/// [SignalOccurrence] object if available. This is the hierarchy-only portion
/// of search results; UI layers can use the pre-computed display helpers
/// directly without re-parsing paths.
@immutable
class SignalSearchResult extends HierarchySearchResult {
  /// Alias for [id] — the signal's full hierarchical path.
  String get signalId => id;

  /// The underlying [SignalOccurrence] from the hierarchy service (if
  /// available). Contains width, direction, and other signal metadata.
  final SignalOccurrence? signal;

  /// Creates a signal search result.
  const SignalSearchResult({
    required String signalId,
    required super.path,
    this.signal,
  }) : super(id: signalId);

  /// Occurrence names that need to be expanded to reveal this signal.
  ///
  /// These are the intermediate path segments between the top occurrence
  /// and the signal name — i.e. everything except the first (top
  /// occurrence) and last (signal name) segments.
  ///
  /// For `Top/sub1/sub2/clk` this returns `["sub1", "sub2"]`.
  List<String> get intermediateOccurrenceNames =>
      path.length > 2 ? path.sublist(1, path.length - 1) : const <String>[];

  @override
  String toString() => 'SignalSearchResult($id, width=${signal?.width ?? "?"})';
}

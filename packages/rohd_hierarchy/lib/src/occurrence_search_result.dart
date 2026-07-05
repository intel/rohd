// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// occurrence_search_result.dart
// Result of a module/node search with enriched metadata.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';

import 'package:rohd_hierarchy/src/hierarchy_occurrence.dart';
import 'package:rohd_hierarchy/src/hierarchy_search_result.dart';

/// Result of an occurrence search with enriched metadata.
///
/// Contains the occurrence's full path, parsed path segments, and the full
/// [HierarchyOccurrence] object. This mirrors `SignalSearchResult` for
/// occurrences and provides a consistent search results interface.
@immutable
class OccurrenceSearchResult extends HierarchySearchResult {
  /// Alias for [id] — the occurrence's full hierarchical path.
  String get occurrenceId => id;

  /// The underlying [HierarchyOccurrence] from the hierarchy service.
  /// Contains the occurrence's name, type, children, and signals.
  final HierarchyOccurrence occurrence;

  /// Creates an occurrence search result.
  const OccurrenceSearchResult({
    required String occurrenceId,
    required super.path,
    required this.occurrence,
  }) : super(id: occurrenceId);

  /// Whether this occurrence has sub-hierarchy (i.e. is not a primitive
  /// leaf).
  bool get isModule => !occurrence.isPrimitive;

  /// Number of direct child occurrences.
  int get childCount => occurrence.children.length;

  @override
  String toString() => 'OccurrenceSearchResult($id)';
}

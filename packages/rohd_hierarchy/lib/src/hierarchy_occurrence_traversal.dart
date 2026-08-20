// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_occurrence_traversal.dart
// Child traversal over live hierarchy occurrences.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/hierarchy_occurrence.dart';

/// Controls whether child traversal crosses non-leaf hierarchy boundaries.
enum OccurrenceTraversalMode {
  /// Return only direct children.
  opaque,

  /// Descend through non-leaf children and return the first leaf occurrences.
  transparent,
}

/// Child traversal available directly on a live hierarchy occurrence handle.
extension HierarchyOccurrenceTraversal on HierarchyOccurrence {
  /// Returns child occurrence handles matching [pattern].
  ///
  /// [OccurrenceTraversalMode.opaque] evaluates direct children.
  /// [OccurrenceTraversalMode.transparent] crosses non-leaf children and
  /// evaluates only the first leaf occurrences reached on each branch.
  List<HierarchyOccurrence> childrenMatching({
    Pattern? pattern,
    OccurrenceTraversalMode mode = OccurrenceTraversalMode.opaque,
  }) {
    final candidates = mode == OccurrenceTraversalMode.opaque
        ? children
        : _transparentChildren();
    return candidates
        .where((child) =>
            pattern == null || pattern.allMatches(child.name).isNotEmpty)
        .toList();
  }

  List<HierarchyOccurrence> _transparentChildren() {
    final leaves = <HierarchyOccurrence>[];
    void collect(HierarchyOccurrence occurrence) {
      if (occurrence.children.isEmpty) {
        leaves.add(occurrence);
        return;
      }
      occurrence.children.forEach(collect);
    }

    children.forEach(collect);
    return leaves;
  }
}

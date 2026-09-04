// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_extensions.dart
// Convenience extensions for HierarchyOccurrence checks.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Convenience helpers for [HierarchyOccurrence] nodes.
extension HierarchyOccurrenceExtensions on HierarchyOccurrence {
  /// True when this node is the top/root of the provided [service].
  ///
  /// If [service] is omitted, falls back to `parent == null` which
  /// matches nodes that have not been parented (root of the tree).
  bool isTop([HierarchyService? service]) {
    if (service != null) {
      return path() == service.root.path();
    }
    return parent == null;
  }
}

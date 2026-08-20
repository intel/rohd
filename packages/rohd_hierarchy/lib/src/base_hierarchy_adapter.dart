// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// base_hierarchy_adapter.dart
// Base class with shared implementation for hierarchy adapters.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/hierarchy_models.dart';
import 'package:rohd_hierarchy/src/hierarchy_service.dart';

/// Base class providing shared implementation for hierarchy adapters.
///
/// The [HierarchyOccurrence] tree rooted at [root] is the single source of
/// truth. Children and signals are read directly from each occurrence's
/// [HierarchyOccurrence.children] and [HierarchyOccurrence.signals] lists.
/// Lookups use [OccurrenceAddress]-based navigation.
///
/// Concrete adapters should:
/// 1. Extend this class
/// 2. Build a complete [HierarchyOccurrence] tree (with children and signals
///    populated on each occurrence)
/// 3. Set the [root] occurrence
///
/// Search, autocomplete, and signal lookup are implemented by
/// [HierarchyService] via recursive tree walking.
abstract class BaseHierarchyAdapter with HierarchyService {
  HierarchyOccurrence? _root;

  /// Creates a [BaseHierarchyAdapter].
  BaseHierarchyAdapter();

  /// Creates an adapter wrapping an existing [HierarchyOccurrence] tree.
  ///
  /// The tree itself is the single source of truth — children and signals
  /// are read directly from the [HierarchyOccurrence] lists.
  ///
  /// Example usage:
  /// ```dart
  /// final treeRoot = await dataSource.evalModuleTree();
  /// final service = BaseHierarchyAdapter.fromTree(treeRoot);
  /// final paths = service.searchSignalPaths('clk');
  /// ```
  factory BaseHierarchyAdapter.fromTree(
    HierarchyOccurrence rootNode,
  ) = _TreeBackedAdapter;

  /// Sets the root occurrence.  Call this once during initialisation.
  set root(HierarchyOccurrence node) {
    _root = node;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HierarchyService concrete accessors — all tree-walking, no flat maps
  // ─────────────────────────────────────────────────────────────────────────

  @override
  HierarchyOccurrence get root {
    if (_root == null) {
      throw StateError(
          'Root occurrence not set. Call setRoot() during initialization.');
    }
    return _root!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tree-backed implementation returned by BaseHierarchyAdapter.fromTree()
// ─────────────────────────────────────────────────────────────────────────────

/// Private adapter that wraps an existing [HierarchyOccurrence] tree.
///
/// Children and signals are read directly from the tree occurrences.
class _TreeBackedAdapter extends BaseHierarchyAdapter {
  _TreeBackedAdapter(HierarchyOccurrence rootNode) {
    root = rootNode;
    rootNode.buildAddresses();
  }
}

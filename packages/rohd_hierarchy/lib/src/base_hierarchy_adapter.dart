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
/// The [HierarchyNode] tree rooted at [root] is the single source of truth.
/// Children and signals are read directly from each node's
/// [HierarchyNode.children] and [HierarchyNode.signals] lists.
/// Lookups use [HierarchyAddress]-based navigation.
///
/// Concrete adapters should:
/// 1. Extend this class
/// 2. Build a complete [HierarchyNode] tree (with children and signals
///    populated on each node)
/// 3. Set the [root] node
///
/// Search, autocomplete, and signal lookup are implemented by
/// [HierarchyService] via recursive tree walking.
abstract class BaseHierarchyAdapter with HierarchyService {
  HierarchyNode? _root;

  /// Creates a [BaseHierarchyAdapter].
  BaseHierarchyAdapter();

  /// Creates an adapter wrapping an existing [HierarchyNode] tree.
  ///
  /// The tree itself is the single source of truth — children and signals
  /// are read directly from the [HierarchyNode] lists.
  ///
  /// Example usage:
  /// ```dart
  /// final treeRoot = await dataSource.evalModuleTree();
  /// final service = BaseHierarchyAdapter.fromTree(treeRoot);
  /// final children = service.children(service.root.id);
  /// ```
  factory BaseHierarchyAdapter.fromTree(
    HierarchyNode rootNode,
  ) = _TreeBackedAdapter;

  /// Sets the root node.  Call this once during initialisation.
  set root(HierarchyNode node) {
    _root = node;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HierarchyService concrete accessors — all tree-walking, no flat maps
  // ─────────────────────────────────────────────────────────────────────────

  @override
  HierarchyNode get root {
    if (_root == null) {
      throw StateError(
          'Root node not set. Call setRoot() during initialization.');
    }
    return _root!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tree-backed implementation returned by BaseHierarchyAdapter.fromTree()
// ─────────────────────────────────────────────────────────────────────────────

/// Private adapter that wraps an existing [HierarchyNode] tree.
///
/// Children and signals are read directly from the tree nodes.
class _TreeBackedAdapter extends BaseHierarchyAdapter {
  _TreeBackedAdapter(HierarchyNode rootNode) {
    root = rootNode;
  }
}

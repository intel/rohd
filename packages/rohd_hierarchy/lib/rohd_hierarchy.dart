// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_hierarchy.dart
// Main library export for rohd_hierarchy package.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Generic hierarchy data models for hardware module navigation.
///
/// This library provides source-agnostic data models for representing
/// hardware module hierarchies:
///
/// ## Core Data Models
/// - [HierarchyAddress] - Efficient index-based addressing for tree navigation
/// - [HierarchyNode] - A node in the module hierarchy (module or instance)
/// - [HierarchyKind] - Enum for node types (module, instance)
/// - [Signal] - A signal in the hierarchy (wire, reg, port)
/// - [Port] - An I/O port on a module (Signal subclass)
///
/// ## Search & Navigation
/// - [SignalSearchResult] - Result of a signal search with enriched metadata
/// - [ModuleSearchResult] - Result of a module search with enriched metadata
/// - [HierarchyService] - Abstract interface for hierarchy navigation
/// - [HierarchySearchController] - Pure Dart search state controller
///
/// ## Adapters
/// - [BaseHierarchyAdapter] - Base class with shared adapter implementation
/// - [NetlistHierarchyAdapter] - Adapter for netlist format (Yosys JSON / ROHD)
///
/// This package has no dependencies and can be used standalone by any
/// application that needs to navigate hardware hierarchies.
///
/// ## Quick Start
/// ```dart
/// // 1. Create hierarchy
/// final root = HierarchyNode(id: 'top', name: 'top',
/// kind: HierarchyKind.module);
/// root.buildAddresses();  // Enable address-based navigation
///
/// // 2. Search
/// final service = BaseHierarchyAdapter.fromTree(root);
/// final results = service.searchSignals('clk');
/// ```
library;

export 'src/base_hierarchy_adapter.dart';
export 'src/hierarchy_models.dart';
export 'src/hierarchy_search_controller.dart';
export 'src/hierarchy_service.dart';
export 'src/netlist_hierarchy_adapter.dart';

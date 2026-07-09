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
/// - `OccurrenceAddress` - Efficient index-based addressing for tree navigation
/// - `HierarchyOccurrence` - An occurrence of a module definition in the tree
/// - `SignalOccurrence` - A signal in the hierarchy
///
/// ## Search & Navigation
/// - `SignalSearchResult` - Result of a signal search with enriched metadata
/// - `OccurrenceSearchResult` - Result of an occurrence search with metadata
/// - `HierarchyService` - Abstract interface for hierarchy navigation
/// - `HierarchySearchController` - Pure Dart search state controller
///
/// ## Adapters
/// - `BaseHierarchyAdapter` - Base class with shared adapter implementation
/// - `NetlistHierarchyAdapter` - Adapter for netlist JSON format
///
/// This package has no dependencies and can be used standalone by any
/// application that needs to navigate hardware hierarchies.
///
/// ## Quick Start
/// ```dart
/// 1. Create hierarchy
/// final root = HierarchyOccurrence(id: 'top', name: 'top');
/// root.buildAddresses();  // Enable address-based navigation
///
/// 2. Search
/// final service = BaseHierarchyAdapter.fromTree(root);
/// final results = service.searchSignals('clk');
/// ```
library;

export 'src/base_hierarchy_adapter.dart';
export 'src/hierarchy_models.dart';
export 'src/hierarchy_query.dart';
export 'src/hierarchy_search_controller.dart';
export 'src/hierarchy_service.dart';
export 'src/netlist_hierarchy_adapter.dart';

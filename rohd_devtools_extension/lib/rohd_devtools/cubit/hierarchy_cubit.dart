// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_cubit.dart
// Unified hierarchy state management for DevTools. This cubit owns the
// HierarchyOccurrence tree and provides it to embedded viewers.
//
// 2026 January Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// State representing the current hierarchy data.
sealed class DevToolsHierarchyState extends Equatable {
  const DevToolsHierarchyState();
}

/// Initial state - no hierarchy loaded.
class HierarchyNotLoaded extends DevToolsHierarchyState {
  /// Constructor for not loaded state.
  const HierarchyNotLoaded();

  @override
  List<Object?> get props => [];
}

/// Loading state - hierarchy is being loaded.
class HierarchyLoading extends DevToolsHierarchyState {
  /// Constructor for loading state.
  const HierarchyLoading();

  @override
  List<Object?> get props => [];
}

/// Loaded state - hierarchy is available.
class HierarchyLoaded extends DevToolsHierarchyState {
  /// The root hierarchy node.
  final HierarchyOccurrence root;

  /// The hierarchy service for navigating the tree.
  /// Can be used by embedded viewers for signal search, etc.
  final HierarchyService? hierarchyService;

  /// Optional selected module.
  final HierarchyOccurrence? selectedModule;

  /// Constructor for loaded state.
  const HierarchyLoaded({
    required this.root,
    this.hierarchyService,
    this.selectedModule,
  });

  /// Create a copy of this state with optional new values.
  HierarchyLoaded copyWith({
    HierarchyOccurrence? root,
    HierarchyService? hierarchyService,
    HierarchyOccurrence? selectedModule,
    bool clearSelectedModule = false,
  }) =>
      HierarchyLoaded(
        root: root ?? this.root,
        hierarchyService: hierarchyService ?? this.hierarchyService,
        selectedModule: clearSelectedModule
            ? null
            : (selectedModule ?? this.selectedModule),
      );

  @override
  List<Object?> get props => [
        root.path(),
        hierarchyService,
        selectedModule?.path(),
      ];
}

/// Error state - hierarchy loading failed.
class HierarchyError extends DevToolsHierarchyState {
  /// Error message.
  final String message;

  /// Constructor for error state.
  const HierarchyError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Cubit that manages the shared hierarchy state for DevTools.
///
/// This cubit is the single source of truth for hierarchy data.
/// Embedded viewers (Wave Viewer, Schematic Viewer) should listen to
/// this cubit rather than loading their own hierarchy.
class DevToolsHierarchyCubit extends Cubit<DevToolsHierarchyState> {
  /// Constructor for the cubit, starts with no hierarchy loaded.
  DevToolsHierarchyCubit() : super(const HierarchyNotLoaded());

  /// Load hierarchy from a HierarchyOccurrence (e.g., from ROHD inspector
  /// JSON).
  ///
  /// If no [service] is provided, a [BaseHierarchyAdapter.fromTree] adapter is
  /// automatically created to wrap the node tree, enabling signal search and
  /// navigation.
  void loadFromNode(HierarchyOccurrence root, {HierarchyService? service}) {
    // Create a service if not provided - fromTree wraps the tree
    final hierarchyService = service ?? BaseHierarchyAdapter.fromTree(root);
    emit(HierarchyLoaded(root: root, hierarchyService: hierarchyService));
  }

  /// Load hierarchy from an adapter that implements HierarchyService.
  void loadFromAdapter(HierarchyService adapter) {
    emit(HierarchyLoaded(root: adapter.root, hierarchyService: adapter));
  }

  /// Set loading state.
  void setLoading() {
    emit(const HierarchyLoading());
  }

  /// Set error state.
  void setError(String message) {
    emit(HierarchyError(message));
  }

  /// Clear hierarchy.
  void clear() {
    emit(const HierarchyNotLoaded());
  }

  /// Select a module in the hierarchy.
  void selectModule(HierarchyOccurrence? module) {
    final currentState = state;
    if (currentState is HierarchyLoaded) {
      if (module == null) {
        emit(currentState.copyWith(clearSelectedModule: true));
      } else {
        emit(currentState.copyWith(selectedModule: module));
      }
    }
  }

  /// Get the current root node if loaded.
  HierarchyOccurrence? get currentRoot {
    final currentState = state;
    if (currentState is HierarchyLoaded) {
      return currentState.root;
    }
    return null;
  }

  /// Get the current hierarchy service if loaded.
  HierarchyService? get currentService {
    final currentState = state;
    if (currentState is HierarchyLoaded) {
      return currentState.hierarchyService;
    }
    return null;
  }

  /// Get the currently selected module if any.
  HierarchyOccurrence? get selectedModule {
    final currentState = state;
    if (currentState is HierarchyLoaded) {
      return currentState.selectedModule;
    }
    return null;
  }
}

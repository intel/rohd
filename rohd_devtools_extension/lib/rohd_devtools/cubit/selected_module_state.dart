// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_module_state.dart
// States for the selected module cubit.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

part of 'selected_module_cubit.dart';

/// Base state for the currently selected module.
abstract class SelectedModuleState extends Equatable {
  /// Creates a selected-module state.
  const SelectedModuleState();

  @override
  List<Object?> get props => [];
}

/// State emitted when no module is selected.
class SelectedModuleInitial extends SelectedModuleState {}

/// State emitted when a module has been selected.
class SelectedModuleLoaded extends SelectedModuleState {
  /// The currently selected module.
  final TreeModel module;

  /// Creates a loaded state with the selected module.
  const SelectedModuleLoaded(this.module);

  @override
  List<Object?> get props => [module];
}

// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_module_state.dart
// States for the selected module cubit.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

part of 'selected_module_cubit.dart';

abstract class SelectedModuleState extends Equatable {
  const SelectedModuleState();

  @override
  List<Object?> get props => [];
}

class SelectedModuleInitial extends SelectedModuleState {}

class SelectedModuleLoaded extends SelectedModuleState {
  final TreeModel module;

  const SelectedModuleLoaded(this.module);

  @override
  List<Object?> get props => [module];
}

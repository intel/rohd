// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_module_cubit.dart
// Cubit for the selected module.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

part 'selected_module_state.dart';

/// Cubit that tracks which module is currently selected.
class SelectedModuleCubit extends Cubit<SelectedModuleState> {
  /// Creates the selected-module cubit.
  SelectedModuleCubit() : super(SelectedModuleInitial());

  /// Selects a module and emits the loaded state.
  void setModule(TreeModel module) {
    emit(SelectedModuleLoaded(module));
  }
}

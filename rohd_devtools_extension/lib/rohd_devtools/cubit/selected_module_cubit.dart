// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_view.dart
// Main view for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

part 'selected_module_state.dart';

class SelectedModuleCubit extends Cubit<SelectedModuleState> {
  SelectedModuleCubit() : super(SelectedModuleInitial());

  void setModule(TreeModel module) {
    emit(SelectedModuleLoaded(module));
  }
}

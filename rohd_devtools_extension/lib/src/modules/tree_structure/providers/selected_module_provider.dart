// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_module_provider.dart
// Provider to track module selected by user.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';

part 'selected_module_provider.g.dart';

@riverpod
class SelectedModule extends _$SelectedModule {
  @override
  TreeModel? build() {
    return null;
  }

  void setModule(TreeModel module) {
    state = module;
  }
}

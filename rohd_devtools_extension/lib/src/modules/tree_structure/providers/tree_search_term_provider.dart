// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_search_term_provider.dart
// Provider to track the search keywords from user.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tree_search_term_provider.g.dart';

@riverpod
class TreeSearchTerm extends _$TreeSearchTerm {
  @override
  String? build() {
    return null;
  }

  void setTerm(String term) {
    state = term;
  }
}

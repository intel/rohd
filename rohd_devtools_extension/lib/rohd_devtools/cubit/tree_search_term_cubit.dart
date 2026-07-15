// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_search_term_cubit.dart
// Cubit for the tree search term.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit that stores the current tree search term.
class TreeSearchTermCubit extends Cubit<String?> {
  /// Creates the tree-search cubit with no initial term.
  TreeSearchTermCubit() : super(null);

  /// Updates the search term.
  void setTerm(String term) {
    emit(term);
  }
}

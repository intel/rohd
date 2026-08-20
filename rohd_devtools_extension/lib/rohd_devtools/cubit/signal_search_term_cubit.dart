// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_search_term_cubit.dart
// Cubit for the signal search term.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit that stores the current signal-table search term.
class SignalSearchTermCubit extends Cubit<String?> {
  /// Creates the signal-search cubit with no initial term.
  SignalSearchTermCubit() : super(null);

  /// Updates the search term.
  void setTerm(String term) {
    emit(term);
  }
}

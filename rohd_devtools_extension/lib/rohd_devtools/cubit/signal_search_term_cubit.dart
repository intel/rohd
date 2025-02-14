// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_search_term_cubit.dart
// Cubit for the signal search term.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

class SignalSearchTermCubit extends Cubit<String?> {
  SignalSearchTermCubit() : super(null);

  void setTerm(String term) {
    emit(term);
  }
}

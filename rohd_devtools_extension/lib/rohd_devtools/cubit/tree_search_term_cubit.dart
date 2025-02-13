// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_view.dart
// Main view for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

class TreeSearchTermCubit extends Cubit<String?> {
  TreeSearchTermCubit() : super(null);

  void setTerm(String term) {
    emit(term);
  }
}

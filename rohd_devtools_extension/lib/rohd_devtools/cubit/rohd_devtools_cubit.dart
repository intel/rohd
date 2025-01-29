// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_cubit.dart
// Implementation fo a cubit for Rohd Devtools.
//
// 2025 January 28

import 'package:bloc/bloc.dart';

class RohdDevToolsCubit extends Cubit<int> {
  /// {@macro counter_cubit}
  RohdDevToolsCubit() : super(0);

  /// Add 1 to the current state.
  void increment() => emit(state + 1);

  /// Subtract 1 from the current state.
  void decrement() => emit(state - 1);
}

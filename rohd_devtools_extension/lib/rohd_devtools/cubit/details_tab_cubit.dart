// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// details_tab_cubit.dart
// Cubit for managing the selected tab in module details view.
//
// 2025 January 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

/// Enum representing the available tabs in the module details view.
enum DetailsTab {
  /// Details tab showing module information.
  details,

  /// Waveform tab showing signal waveforms.
  waveform,

  /// Schematic tab showing module schematics.
  schematic,
}

/// Cubit for managing the selected tab state.
class DetailsTabCubit extends Cubit<DetailsTab> {
  /// Initializes the cubit with the default tab as [DetailsTab.details].
  DetailsTabCubit() : super(DetailsTab.details);

  /// Sets the currently selected tab.
  void selectTab(DetailsTab tab) => emit(tab);
}

// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_service.dart
// Services for signal's logic.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';

/// Utility methods for signal filtering and lookup.
abstract class SignalService {
  /// Filters signals by case-insensitive name match.
  static List<SignalModel> filterSignals(
    List<SignalModel> signals,
    String searchTerm,
  ) {
    final filteredSignals = <SignalModel>[];

    for (final signal in signals) {
      if (signal.name.toLowerCase().contains(searchTerm.toLowerCase())) {
        filteredSignals.add(signal);
      }
    }

    return filteredSignals;
  }
}

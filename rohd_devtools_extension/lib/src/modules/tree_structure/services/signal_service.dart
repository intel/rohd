// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_service.dart
// Services for signal's logic.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_devtools_extension/src/modules/tree_structure/models/signal_model.dart';

class SignalService {
  List<SignalModel> filterSignals(
    List<SignalModel> signals,
    String searchTerm,
  ) {
    List<SignalModel> filteredSignals = [];

    for (var signal in signals) {
      if (signal.name.toLowerCase().contains(searchTerm.toLowerCase())) {
        filteredSignals.add(signal);
      }
    }

    return filteredSignals;
  }
}

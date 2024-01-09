// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_service.dart
// Services for signal's logic.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

class SignalService {
  Map<String, dynamic> filterSignals(
    Map<String, dynamic> signals,
    String searchTerm,
  ) {
    Map<String, dynamic> filtered = {};

    signals.forEach((name, value) {
      if (name.toLowerCase().contains(searchTerm.toLowerCase())) {
        filtered[name] = value;
      }
    });

    return filtered;
  }
}

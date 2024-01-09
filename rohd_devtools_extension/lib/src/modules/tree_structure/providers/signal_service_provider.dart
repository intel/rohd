// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_service_provider.dart
// Provider to communicate with signal's service.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';

part 'signal_service_provider.g.dart';

@riverpod
SignalService signalService(SignalServiceRef ref) {
  return SignalService();
}

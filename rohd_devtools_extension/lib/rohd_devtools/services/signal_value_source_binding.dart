// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_source_binding.dart
// Repo-specific binding for live signal value source creation.

import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';
import 'package:vm_service/vm_service.dart' as vm;

/// Creates the repo-specific live signal value source for [treeService].
///
/// The local overlay keeps live-value production in the waveform stack, so the
/// cubit-level binding is currently absent.
SignalValueSource? createSignalValueSourceBinding({
  required TreeService treeService,
  required vm.VmService vmService,
}) =>
    null;

/// Dispose any repo-specific live signal value source instance.
Future<void> disposeSignalValueSourceBinding(
  SignalValueSource? signalValueSource,
) async {}

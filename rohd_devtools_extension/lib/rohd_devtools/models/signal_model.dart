import 'package:rohd_hierarchy/rohd_hierarchy.dart';

export 'package:rohd_hierarchy/rohd_hierarchy.dart' show SignalOccurrence;
// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_model.dart
// Model of the signal to be tabulate on the detail table.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

// Re-export SignalOccurrence as SignalModel for backwards compatibility.
// New code should import rohd_hierarchy directly.

/// Typedef for backwards compatibility.
/// @deprecated Use [SignalOccurrence] directly.
typedef SignalModel = SignalOccurrence;

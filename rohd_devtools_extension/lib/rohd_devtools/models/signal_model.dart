// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_model.dart
// Model of a signal in the ROHD DevTools extension.
//
// 2026 September 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

export 'package:rohd_hierarchy/rohd_hierarchy.dart' show SignalOccurrence;

// Re-export SignalOccurrence as SignalModel for backwards compatibility.
// New code should import rohd_hierarchy directly.

/// Typedef for backwards compatibility.
/// @deprecated Use [SignalOccurrence] directly.
typedef SignalModel = SignalOccurrence;

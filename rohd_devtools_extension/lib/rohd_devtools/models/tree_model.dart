// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.dart
// Model of the ROHD DevTools hierarchy tree.
//
// 2026 September 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

export 'package:rohd_hierarchy/rohd_hierarchy.dart' show HierarchyOccurrence;

// Re-export HierarchyOccurrence as TreeModel for backwards compatibility.
// New code should import rohd_hierarchy directly.

/// Typedef for backwards compatibility.
/// @deprecated Use [HierarchyOccurrence] directly.
typedef TreeModel = HierarchyOccurrence;

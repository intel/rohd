import 'package:rohd_hierarchy/rohd_hierarchy.dart';

export 'package:rohd_hierarchy/rohd_hierarchy.dart' show HierarchyOccurrence;
// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.dart
// Model of the module tree hierarchy.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

// Re-export HierarchyOccurrence as TreeModel for backwards compatibility.
// New code should import rohd_hierarchy directly.

/// Typedef for backwards compatibility.
/// @deprecated Use [HierarchyOccurrence] directly.
typedef TreeModel = HierarchyOccurrence;

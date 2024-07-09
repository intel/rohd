// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_hierarchy_exception.dart
// Definition for exception when an invalid hierarchy is detected.
//
// 2024 April 12
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a constructed hierarchy is illegal.
class InvalidHierarchyException extends RohdException {
  /// Constructs a new [Exception] for when a constructed hierarchy is illegal.
  InvalidHierarchyException(super.message);
}

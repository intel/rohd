// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_op.dart
// Common contract for hardware operations with typed outputs.
//
// 2026 September 2
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// A hardware operation whose output preserves the requested [Logic] type.
abstract class TypedOp<LogicType extends Logic> extends Module {
  /// The output produced by this operation.
  LogicType get out;

  /// Creates a typed operation.
  TypedOp({
    super.name = 'typed_op',
    super.reserveName,
    super.definitionName,
    super.reserveDefinitionName,
  });
}

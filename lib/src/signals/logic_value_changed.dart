// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_changed.dart
// Definition of an event when a signal value changes.
//
// 2023 May 26
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Represents the event of a [Logic] changing value.
class LogicValueChanged {
  /// The newly updated value of the [Logic].
  final LogicValue newValue;

  /// The previous value of the [Logic].
  final LogicValue previousValue;

  /// Represents the event of a [Logic] changing value from [previousValue]
  /// to [newValue].
  const LogicValueChanged(this.newValue, this.previousValue);

  @override
  String toString() => '$previousValue  -->  $newValue';
}

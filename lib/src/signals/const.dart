// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// const.dart
// Definition of signals with constant values.
//
// 2023 May 26
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Represents a [Logic] that never changes value.
class Const extends Logic {
  /// Constructs a [Const] with the specified value.
  ///
  /// [val] should be processable by [LogicValue.of].
  Const(dynamic val, {int? width, bool fill = false})
      : super(
          name: 'const_$val',
          width: val is LogicValue ? val.width : width ?? 1,
          // we don't care about maintaining this node unless necessary
          naming: Naming.unnamed,
        ) {
    put(val, fill: fill);
    _unassignable = true;
  }
}

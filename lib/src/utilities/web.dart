// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// web.dart
// Utilities for running ROHD safely on the web or in JavaScript.
//
// 2023 December 8
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Borrowed from Flutter's implementation to determine whether Dart is
/// compiled to run on the web.  This is relevant for ROHD because when the
/// code is compiled to JavaScript, it affects the ability for [LogicValue]
/// to store different sizes of data in different implementations.
///
/// See more details here:
/// https://api.flutter.dev/flutter/foundation/kIsWeb-constant.html
// ignore: do_not_use_environment
const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');

/// The number of bits in an int.
// ignore: constant_identifier_names
const int INT_BITS = kIsWeb ? 32 : 64;

/// Calculates the `int` result of `1 << shamt` in a safe way considering
/// whether it is run in JavaScript or native Dart.
///
/// In JavaScript, the shift amount is `&`ed with `0x1f`, so `1 << 32 == 0`.
int oneSllBy(int shamt) {
  if (kIsWeb) {
    if (shamt > 64 || shamt < 0) {
      return 0;
    } else if (shamt & 0x1f != shamt) {
      var result = 1 << 0x1f;
      var remainingToShift = shamt - 0x1f;

      while (remainingToShift > 0) {
        result *= 2;
        remainingToShift--;
      }

      return result;
    } else {
      return 1 << shamt;
    }
  } else {
    return 1 << shamt;
  }
}

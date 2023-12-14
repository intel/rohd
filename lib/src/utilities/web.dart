// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// web.dart
// Utilities for running ROHD safely on the web or in JavaScript.
//
// 2023 December 8
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:math';

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
    assert(shamt <= 52, 'Loss of precision in JavaScript beyond 53 bits.');
    return pow(2, shamt) as int;
  } else {
    return 1 << shamt;
  }
}

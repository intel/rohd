/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// non_supported_type_exception.dart
/// An exception that is thrown when simcompare
/// yield difference result from expectation
///
/// 2022 November 15
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/rohd.dart';

/// Throws [NonSupportedTypeException] whenever the vectors
/// expected from simulator comparison is difference from
/// the output from [Module] simulated.
///
class NonSupportedTypeException implements Exception {
  late final String _message;

  /// constructor for NonSupportedTypeException,
  /// pass custom String [message] to the constructor to override
  NonSupportedTypeException(String value,
      [String message = 'The runtimetype of expected vector is unsupported: '])
      : _message = message + value.runtimeType.toString();

  @override
  String toString() => _message;
}

/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_output_value_exception.dart
/// An exception that is thrown when simcompare
/// yield difference result from expectation
///
/// 2022 November 17
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/rohd.dart';

import 'package:rohd/src/utilities/simcompare.dart';

/// Throws [MismatchOutputValueException] whenever the vectors
/// expected from simulator comparison is difference from
/// the output from [Module] simulated.
///
class MismatchOutputValueException implements Exception {
  late final String _message;

  /// constructor for NonSupportedTypeException,
  /// pass custom String [message] to the constructor to override
  MismatchOutputValueException(
      List<Vector> vectors, Vector vector, Logic output, dynamic expectedValue,
      [String? message]) {
    final errorReason = 'For vector #${vectors.indexOf(vector)} $vector,'
        ' expected $output to be $expectedValue, but it was ${output.value}.';
    _message = message ?? errorReason;
  }

  @override
  String toString() => _message;
}

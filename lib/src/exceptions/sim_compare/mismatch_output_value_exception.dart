/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_output_value_exception.dart
/// An exception that thrown when simcompare
/// yield difference result from expectation.
///
/// 2022 November 17
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/rohd.dart';

import 'package:rohd/src/utilities/simcompare.dart';

/// An exception that thrown when the vectors
/// expected from [SimCompare] are difference from
/// [Module] simulated output.
class MismatchOutputValueException implements Exception {
  late final String _message;

  /// Displays output values that are different between
  /// expected and simulated vectors with default error [message].
  ///
  /// Creates a [MismatchOutputValueException] with an optional error [message].
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

/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// non_supported_type_exception.dart
/// An exception that thrown when `runtimetype` of expected
/// vector output from SimCompare is invalid or unsupported.
///
/// 2022 November 17
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/src/utilities/simcompare.dart';

/// An exception that thrown when `runtimeType` of expected vector
/// output from [SimCompare] is invalid or unsupported.
class NonSupportedTypeException implements Exception {
  late final String _message;

  /// Displays [vector] which have invalid or unsupported `runtimeType`.
  ///
  /// Creates a [NonSupportedTypeException] with an optional error [message].
  NonSupportedTypeException(String vector,
      [String message = 'The runtimetype of expected vector is unsupported: '])
      : _message = message + vector.runtimeType.toString();

  @override
  String toString() => _message;
}

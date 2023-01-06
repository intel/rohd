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

import 'package:rohd/src/exceptions/rohd_exception.dart';
import 'package:rohd/src/utilities/simcompare.dart';

/// An exception that thrown when `runtimeType` of expected vector
/// output from [SimCompare] is invalid or unsupported.
class NonSupportedTypeException extends RohdException {
  /// Displays [vector] which have invalid or unsupported `runtimeType`
  /// with default error [message].
  ///
  /// Creates a [NonSupportedTypeException] with an optional error [message].
  NonSupportedTypeException(String vector,
      [String message = 'The runtimetype of expected vector is unsupported: '])
      : super(message + vector.runtimeType.toString());
}

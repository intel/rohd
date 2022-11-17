/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// non_supported_type_exception.dart
/// An exception that is thrown when runtimetype of expected
/// vector output is not supported.
///
/// 2022 November 17
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

/// Throws [NonSupportedTypeException] whenever the vectors
/// expected from simulator comparison is invalid or unsupported.
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

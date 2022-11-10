/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// name_exception.dart
/// Name Exception that have custom type to be thrown,
///
/// 2022 November 9
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///
class SignalRedrivenException implements Exception {
  late final String _message;

  /// constructor for NullReservedNameException,
  /// pass custom message to the constructor
  SignalRedrivenException(String signals,
      [String message = 'Sequential drove the same signal(s) multiple times: '])
      : _message = message + signals;

  @override
  String toString() => _message;
}

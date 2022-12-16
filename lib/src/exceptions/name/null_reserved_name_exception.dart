/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// null_reserved_name_exception.dart
/// An exception that thrown when a reserved name is `null`.
///
/// 2022 November 15
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

/// An exception that thrown when a reserved name is `null`.
class NullReservedNameException implements Exception {
  late final String _message;

  /// Display error [message] on `null` reserved name.
  ///
  /// Creates a [NullReservedNameException] with an optional error [message].
  NullReservedNameException(
      [String message = 'Reserved Name cannot be null '
          'if reserved name set to true'])
      : _message = message;

  @override
  String toString() => _message;
}

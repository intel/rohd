/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// null_reserved_name_exception.dart
/// An exception that is thrown when reserved name is null
///
/// 2022 November 15
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///
import 'package:rohd/rohd.dart';

/// This Exception show that reserved name eg. definitionName is NULL but
/// reserve flag eg. reserveDefinitionName is set to True.
///
/// Please check on the class [Module] for the constructor argument.
class NullReservedNameException implements Exception {
  late final String _message;

  /// constructor for NullReservedNameException,
  /// pass custom String [message] to the constructor to override
  NullReservedNameException(
      [String message = 'Reserved Name cannot be null '
          'if reserved name set to true'])
      : _message = message;

  @override
  String toString() => _message;
}

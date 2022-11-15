/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_reserved_name_exception.dart
/// An exception that is thrown when reserved name is invalid
///
/// 2022 October 25
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///
import 'package:rohd/rohd.dart';

/// This Exception show that reserved name eg. definitionName naming convention
/// is invalid but reserve flag eg. reserveDefinitionName is set to True.
/// Please check on the syntax of the reservedName.
///
/// Please check on the class [Module] for the constructor argument.
class InvalidReservedNameException implements Exception {
  late final String _message;

  /// constructor for InvalidReservedNameException,
  /// pass custom String [message] to the constructor to override
  InvalidReservedNameException(
      [String message = 'Reserved Name need to follow proper naming '
          'convention if reserved'
          ' name set to true'])
      : _message = message;

  @override
  String toString() => _message;
}

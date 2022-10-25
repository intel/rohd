import 'package:rohd/rohd.dart';

/// This Exception show that reserved name eg. definitionName is NULL but
/// reserve flag eg. reserveDefinitionName is set to True.
///
/// Please check on the class [Module] for the constructor argument.
class NullReservedNameException implements Exception {
  late final String _message;

  /// constructor for NullReservedNameException,
  /// pass custom message to the constructor
  NullReservedNameException(
      [String message = 'Reserved Name cannot be null '
          'if reserved name set to true'])
      : _message = message;

  @override
  String toString() => _message;
}

/// This Exception show that reserved name eg. definitionName naming convention
/// is invalid but reserve flag eg. reserveDefinitionName is set to True.
/// Please check on the syntax of the reservedName.
///
/// Please check on the class [Module] for the constructor argument.
class InvalidReservedNameException implements Exception {
  late final String _message;

  /// constructor for InvalidReservedNameException,
  /// pass custom message to the constructor
  InvalidReservedNameException(
      [String message = 'Reserved Name need to follow proper naming '
          'convention if reserved'
          ' name set to true'])
      : _message = message;

  @override
  String toString() => _message;
}

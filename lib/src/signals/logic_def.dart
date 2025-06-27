part of 'signals.dart';

@internal
sealed class LogicDef extends Logic {
  final bool reserveDefinitionName;

  // TODO: test naming conflicts in generated RTL
  String get definitionName =>
      Sanitizer.sanitizeSV(_definitionName ?? runtimeType.toString());
  final String? _definitionName;

  LogicDef({
    super.width,
    super.name,
    super.naming,
    String? definitionName,
    this.reserveDefinitionName = false,
  }) : _definitionName = Naming.validatedName(definitionName,
            reserveName: reserveDefinitionName);
}

//TODO: file header

part of 'signals.dart';

@internal
sealed class LogicDef extends Logic {
  final bool reserveDefinitionName;

  String get definitionName => _definitionName;
  final String _definitionName;

  LogicDef({
    required String definitionName,
    super.width,
    super.name,
    super.naming,
    this.reserveDefinitionName = false,
  }) : _definitionName = Sanitizer.sanitizeSV(Naming.validatedName(
          definitionName,
          reserveName: reserveDefinitionName,
        )!);
}

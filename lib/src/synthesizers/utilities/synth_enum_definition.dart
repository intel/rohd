import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/namer.dart';

/// Canonical synthesis metadata for an enum type in one module scope.
@immutable
@internal
class SynthEnumDefinition<T extends Enum> {
  /// A representative signal carrying this enum's type information.
  final LogicEnum<T> characteristicEnum;

  /// The generated enum type name.
  final String definitionName;

  /// Generated member names indexed by their Dart enum values.
  final Map<T, String> enumToNameMapping;

  /// Creates or reuses stable generated names through [namer].
  factory SynthEnumDefinition(
    LogicEnum<T> characteristicEnum,
    Namer namer,
  ) {
    final definitionKey = SynthEnumDefinitionKey(characteristicEnum);
    return SynthEnumDefinition._(characteristicEnum, namer, definitionKey);
  }

  SynthEnumDefinition._(
    this.characteristicEnum,
    Namer namer,
    SynthEnumDefinitionKey definitionKey,
  )   : definitionName = namer.identifierNameOf(
          definitionKey,
          initialName: characteristicEnum.definitionName,
          reserved: characteristicEnum.reserveDefinitionName,
        ),
        enumToNameMapping = Map.unmodifiable(characteristicEnum.mapping.map(
          (enumValue, value) => MapEntry(
            enumValue,
            namer.identifierNameOf(
              (definitionKey, enumValue),
              initialName: enumValue.name,
              reserved: characteristicEnum.reserveDefinitionName,
            ),
          ),
        ));
}

/// Equality key for enum definitions that may share one generated typedef.
///
/// The enum values in [enumMapping] retain the Dart enum type as part of their
/// identity. An explicitly reserved definition name also participates in
/// equality, while non-reserved preferred names do not prevent type reuse.
@immutable
@internal
class SynthEnumDefinitionKey {
  /// The enum members and their exact hardware encodings.
  final Map<Enum, LogicValue> enumMapping;

  /// The required type name, or `null` when the name may be uniquified.
  final String? reservedName;

  /// Creates a key describing [characteristicEnum]'s generated type identity.
  SynthEnumDefinitionKey(LogicEnum characteristicEnum)
      : enumMapping = Map.unmodifiable(characteristicEnum.mapping),
        reservedName = characteristicEnum.reserveDefinitionName
            ? characteristicEnum.definitionName
            : null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }

    return other is SynthEnumDefinitionKey &&
        const MapEquality<Enum, LogicValue>()
            .equals(other.enumMapping, enumMapping) &&
        other.reservedName == reservedName;
  }

  @override
  int get hashCode =>
      const MapEquality<Enum, LogicValue>().hash(enumMapping) ^
      reservedName.hashCode;
}

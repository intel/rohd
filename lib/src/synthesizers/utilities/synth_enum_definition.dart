import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/namer.dart';

@immutable
class SynthEnumDefinition<T extends Enum> {
  final LogicEnum<T> characteristicEnum;

  final String definitionName;
  final Map<T, String> enumToNameMapping;

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

@immutable
class SynthEnumDefinitionKey {
  //TODO: finish up this key as a lookup key for SynthEnumDefinition
  final Map<Enum, LogicValue> enumMapping;
  final String? reservedName;
  SynthEnumDefinitionKey(LogicEnum characteristicEnum)
      : enumMapping = characteristicEnum.mapping,
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

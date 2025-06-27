import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

@immutable
class SynthEnumDefinition<T extends Enum> {
  final LogicEnum<T> characteristicEnum;

  final String definitionName;
  final Map<T, String> enumToNameMapping;

  SynthEnumDefinition(this.characteristicEnum, Uniquifier identifierUniquifier)
      : definitionName = identifierUniquifier.getUniqueName(
            initialName: characteristicEnum.definitionName,
            reserved: characteristicEnum.reserveDefinitionName),
        enumToNameMapping = Map.unmodifiable(characteristicEnum.mapping.map(
          (key, value) => MapEntry(
            key,
            identifierUniquifier.getUniqueName(
                initialName: key.name,
                reserved: characteristicEnum.reserveDefinitionName),
          ),
        ));
}

@immutable
class SynthEnumDefinitionKey {
  //TODO: finish up this key as a lookup key for SynthEnumDefinition
  final Map<Enum, String> enumMapping;
  SynthEnumDefinitionKey(LogicEnum characteristicEnum)
      : enumMapping = Map.unmodifiable(characteristicEnum.mapping);
}

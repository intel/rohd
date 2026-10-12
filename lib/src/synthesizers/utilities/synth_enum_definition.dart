// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_enum_definition.dart
// Definition for SynthEnumDefinition.
//
// 2025 June 27
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/namer.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

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
  ///
  /// Set [validateReservedNames] to `false` to plan names for packed output
  /// without rejecting conflicting enum declarations that will not be emitted.
  factory SynthEnumDefinition(
    LogicEnum<T> characteristicEnum,
    Namer namer, {
    bool validateReservedNames = true,
  }) {
    final definitionKey = SynthEnumDefinitionKey(characteristicEnum);
    final definition =
        SynthEnumDefinition._(characteristicEnum, namer, definitionKey);
    if (validateReservedNames && characteristicEnum.reserveDefinitionName) {
      definition._validateReservedNames();
    }
    return definition;
  }

  /// Allocates or reuses type and member names for [definitionKey].
  SynthEnumDefinition._(
    this.characteristicEnum,
    Namer namer,
    SynthEnumDefinitionKey definitionKey,
  )   : definitionName = namer.identifierNameOf(
          definitionKey,
          initialName: characteristicEnum.definitionName,
        ),
        enumToNameMapping = Map.unmodifiable(characteristicEnum.mapping.map(
          (enumValue, value) => MapEntry(
            enumValue,
            namer.identifierNameOf(
              (definitionKey, enumValue),
              initialName: enumValue.name,
            ),
          ),
        ));

  /// Verifies that planned names honor this enum's reserved identifiers.
  void _validateReservedNames() {
    for (final (actual, requested) in [
      (definitionName, characteristicEnum.definitionName),
      for (final entry in enumToNameMapping.entries)
        (entry.value, entry.key.name),
    ]) {
      if (actual != Sanitizer.sanitizeSV(requested)) {
        throw UnavailableReservedNameException(requested);
      }
    }
  }
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

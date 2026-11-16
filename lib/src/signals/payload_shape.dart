// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// payload_shape.dart
// Declared signal shape and semantic metadata.
//
// 2026 November 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'signals.dart';

/// Semantic signal metadata not represented by the hardware layout.
///
/// The identifier must be deterministic and equal exactly when formats are
/// compatible. It should include a domain-specific prefix.
abstract interface class PayloadShapeMetadata {
  /// Stable identifier for this signal's semantic format.
  String get payloadShapeMetadata;
}

/// Whether [signal] declares a shape beyond a plain packed vector.
bool hasDeclaredPayloadShape(Logic signal) =>
    signal is LogicStructure ||
    signal is LogicEnum ||
    signal is PayloadShapeMetadata;

/// Whether two signals declare matching recursive layouts and formats.
///
/// [ignoreConstantNames] permits a constant leaf's generated name to differ
/// from the corresponding driveable clone.
bool sameDeclaredPayloadShape(Logic template, Logic source,
        {bool ignoreConstantNames = false}) =>
    _sameDeclaredPayloadShape(template, source,
        ignoreConstantNames: ignoreConstantNames, allowParentRenaming: false);

bool _sameDeclaredPayloadShape(Logic template, Logic source,
    {required bool ignoreConstantNames, required bool allowParentRenaming}) {
  if (template.width != source.width) {
    return false;
  }
  if (template is PayloadShapeMetadata || source is PayloadShapeMetadata) {
    if (template is! PayloadShapeMetadata ||
        source is! PayloadShapeMetadata ||
        (template as PayloadShapeMetadata).payloadShapeMetadata !=
            (source as PayloadShapeMetadata).payloadShapeMetadata) {
      return false;
    }
  }
  if (template is TypedLogicArray || source is TypedLogicArray) {
    if (template is! TypedLogicArray || source is! TypedLogicArray) {
      return false;
    }
    return template.dimensions.length == source.dimensions.length &&
        template.dimensions.indexed
            .every((d) => d.$2 == source.dimensions[d.$1]) &&
        template.elementWidth == source.elementWidth &&
        template.numUnpackedDimensions == source.numUnpackedDimensions &&
        identical(template.valueCodec, source.valueCodec) &&
        ((template is LogicArray && source is LogicArray) ||
            (template.arrayElements.length == source.arrayElements.length &&
                template.arrayElements.indexed.every((entry) =>
                    _sameDeclaredPayloadShape(
                        entry.$2, source.arrayElements[entry.$1],
                        ignoreConstantNames: ignoreConstantNames,
                        allowParentRenaming: allowParentRenaming))));
  }
  if (template is LogicEnum || source is LogicEnum) {
    return template is LogicEnum &&
        source is LogicEnum &&
        template.mapping.length == source.mapping.length &&
        template.mapping.entries.every((e) => source.mapping[e.key] == e.value);
  }
  if (template is! LogicStructure || source is! LogicStructure) {
    return template is! LogicStructure && source is! LogicStructure;
  }
  return template.elements.length == source.elements.length &&
      template.elements.indexed.every((entry) {
        final other = source.elements[entry.$1];
        return (entry.$2.name == other.name ||
                (allowParentRenaming &&
                    template.name != source.name &&
                    template.name.isNotEmpty &&
                    entry.$2.name.replaceAll(template.name, source.name) ==
                        other.name) ||
                (ignoreConstantNames &&
                    (entry.$2 is Const || other is Const))) &&
            _sameDeclaredPayloadShape(entry.$2, other,
                ignoreConstantNames: ignoreConstantNames,
                allowParentRenaming: allowParentRenaming);
      });
}

/// Whether [clone] preserves declared types and recursive semantic shape.
bool sameTypedCloneShape(Logic source, Logic clone) =>
    !hasDeclaredPayloadShape(source) ||
    (_sameDeclaredPayloadShape(source, clone,
            ignoreConstantNames: true, allowParentRenaming: true) &&
        _sameDeclaredCloneTypes(source, clone));

bool _sameDeclaredCloneTypes(Logic source, Logic clone) {
  if (hasDeclaredPayloadShape(source) &&
      source.runtimeType != clone.runtimeType) {
    return false;
  }
  if (source is TypedLogicArray && clone is TypedLogicArray) {
    return source.arrayElements.indexed.every((entry) =>
        _sameDeclaredCloneTypes(entry.$2, clone.arrayElements[entry.$1]));
  }
  if (source is LogicStructure && clone is LogicStructure) {
    return source.elements.indexed.every(
        (entry) => _sameDeclaredCloneTypes(entry.$2, clone.elements[entry.$1]));
  }
  return true;
}

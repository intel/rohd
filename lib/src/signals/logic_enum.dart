// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_enum.dart
// Definition for LogicEnum.
//
// 2026 July 22
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// A hardware signal constrained to values from a Dart enum [T].
///
/// Each enum member has a unique bit-vector encoding in [mapping].
/// [getsEnum], [put], [inject], and
/// conditional assignments encode enum members using the receiver's mapping,
/// not their [Enum.index]. Members absent from the mapping are rejected.
///
/// Comparisons and [isIn] also encode enum members using [mapping]. Ordering
/// comparisons use numeric encodings, not enum declaration order. Other
/// operands follow [Logic] comparison behavior.
///
/// Unmapped raw values become `x` in simulation; an entirely
/// floating value remains `z`. Constraints apply to the shared connected wire.
class LogicEnum<T extends Enum> extends LogicDef {
  /// The hardware encoding for each supported enum value.
  late final Map<T, LogicValue> mapping;

  /// The enum value represented by the current signal [value].
  ///
  /// Throws a [StateError] when the current value is invalid or unmapped.
  T get valueEnum => mapping.entries
      .firstWhere((entry) => entry.value == value,
          orElse: () => throw StateError(
              'Value $value does not correspond to any enum in $mapping'))
      .key;

  static Map<T, LogicValue> _computeMapping<T extends Enum>(
      {required Map<T, dynamic> mapping, required int width}) {
    final computedMapping = mapping
        .map((key, value) => MapEntry(key, LogicValue.of(value, width: width)));

    if (computedMapping.values.any((v) => !v.isValid)) {
      throw ArgumentError('Mapping values must be valid LogicValues,'
          ' but found: $computedMapping');
    }

    // check that any `int` or `BigInt` mappings actually ended up matching
    for (final MapEntry(:key, value: computedValue)
        in computedMapping.entries) {
      final originalValue = mapping[key];
      if (originalValue is int || originalValue is BigInt) {
        final originalBigInt = originalValue is int
            ? BigInt.from(originalValue)
            : originalValue as BigInt;
        if (computedValue.toBigInt() != originalBigInt) {
          throw ArgumentError(
              'Mapping value for $key cannot be represented at width $width.'
              ' Computed: $computedValue, Original: $originalValue');
        }
      }
    }

    if (computedMapping.values.toSet().length !=
        computedMapping.values.length) {
      throw ArgumentError('Mapping values must be unique,'
          ' but found duplicates: $computedMapping');
    }

    return computedMapping;
  }

  static int _computeWidth<T extends Enum>(
      {int? requestedWidth, Map<T, dynamic>? mapping}) {
    var width = 1;

    if (mapping != null) {
      if (mapping.isEmpty) {
        throw ArgumentError.value(mapping, 'mapping', 'Must not be empty.');
      }

      if (mapping.length > 1) {
        width = LogicValue.ofInt(mapping.length, 32).clog2().toInt();
      }

      if (mapping.values.toSet().length != mapping.values.length) {
        throw ArgumentError(
            'Mapping values must be unique, but found duplicates: $mapping');
      }

      for (final value in mapping.values.whereType<int>()) {
        if (value < 0) {
          throw ArgumentError.value(
              value, 'mapping', 'Negative encodings are not supported.');
        }
        width = max(width, max(1, value.bitLength));
      }

      for (final value in mapping.values.whereType<BigInt>()) {
        if (value.isNegative) {
          throw ArgumentError.value(
              value, 'mapping', 'Negative encodings are not supported.');
        }
        width = max(width, max(1, value.bitLength));
      }

      for (final value in [
        ...mapping.values.whereType<LogicValue>(),
        ...mapping.values.whereType<String>().map(LogicValue.ofString),
        ...mapping.values
            .whereType<Iterable<LogicValue>>()
            .map(LogicValue.ofIterable)
      ]) {
        if (value.width > width) {
          width = value.width;
        }
      }
    }

    if (requestedWidth != null) {
      if (requestedWidth < width) {
        throw ArgumentError(
            'Requested width $requestedWidth is less than the minimum'
            ' required width $width.');
      }
      width = requestedWidth;
    }

    return width;
  }

  /// Converts [values] to sequential encodings in list order.
  ///
  /// Throws an [ArgumentError] if [values] contains duplicate members.
  static Map<T, int> _computeDefaultMapping<T extends Enum>(List<T> values) {
    if (values.toSet().length != values.length) {
      throw ArgumentError.value(
          values, 'values', 'Must not contain duplicates.');
    }
    return Map.fromEntries(
        values.mapIndexed((index, value) => MapEntry(value, index)));
  }

  /// Creates a signal with sequential encodings matching [values] order.
  ///
  /// Throws an [ArgumentError] if [values] is empty or contains duplicates.
  LogicEnum(List<T> values,
      {int? width,
      String? name,
      Naming? naming,
      String? definitionName,
      bool reserveDefinitionName = false})
      : this.withMapping(_computeDefaultMapping(values),
            width: width,
            name: name,
            naming: naming,
            definitionName: definitionName,
            reserveDefinitionName: reserveDefinitionName);

  /// Creates a signal using the explicit hardware encodings in [mapping].
  ///
  /// The width is inferred from the member count and encoding values unless
  /// [width] is provided. If [reserveDefinitionName] is `true`, generated type
  /// and member names cannot be uniquified around collisions.
  LogicEnum.withMapping(
    Map<T, dynamic> mapping, {
    int? width,
    super.name,
    super.naming,
    String? definitionName,
    super.reserveDefinitionName,
  }) : super(
            width: _computeWidth(requestedWidth: width, mapping: mapping),
            definitionName: definitionName ?? T.toString()) {
    this.mapping =
        Map.unmodifiable(_computeMapping(mapping: mapping, width: this.width));

    _wire._constrainValue((value) {
      if (value.isFloating) {
        return LogicValue.filled(this.width, LogicValue.z);
      }
      if (!value.isValid) {
        return LogicValue.filled(this.width, LogicValue.x);
      }
      if (!this.mapping.containsValue(value)) {
        return LogicValue.filled(this.width, LogicValue.x);
      }
      return value;
    });
  }

  /// Drives this [LogicEnum] with a constant value matching the enum [value].
  void getsEnum(T value) {
    if (!mapping.containsKey(value)) {
      throw ArgumentError.value(
          value, 'value', 'Not present in the mapping for $T.');
    }
    gets(Const(mapping[value]));
  }

  /// Connects this signal to a compatible enum, legal constant, or raw logic.
  ///
  /// A [Const] driver must match [width] and have an encoding in [mapping].
  @override
  void gets(Logic other) {
    if (other is LogicEnum && !canAcceptValuesFrom(other)) {
      throw ArgumentError.value(
          other, 'other', 'Enum values must be representable in this mapping.');
    }

    if (other is Const) {
      if (!mapping.containsValue(other.value)) {
        throw ArgumentError.value(
            other.value, 'other', 'Not present in the mapping for $T.');
      }
    }

    super.gets(other);
  }

  /// Creates a conditional assignment from an enum, legal constant, or signal.
  @override
  Conditional operator <(dynamic other) {
    if (_unassignable) {
      throw UnassignableException(this, reason: _unassignableReason);
    }

    if (other is T) {
      return super < (clone()..getsEnum(other));
    } else if (other is Enum) {
      throw ArgumentError.value(other, 'other', 'Must be a value of $T.');
    } else {
      return super < other;
    }
  }

  dynamic _comparisonOperand(dynamic other) {
    if (other is T) {
      final encoding = mapping[other];
      if (encoding == null) {
        throw ArgumentError.value(
            other, 'other', 'Not present in the mapping for $T.');
      }
      return encoding;
    } else if (other is Enum) {
      throw ArgumentError.value(other, 'other', 'Must be a value of $T.');
    }
    return other;
  }

  /// Logical equality, encoding enum members using [mapping].
  @override
  Logic eq(dynamic other) => super.eq(_comparisonOperand(other));

  /// Logical inequality, encoding enum members using [mapping].
  @override
  Logic neq(dynamic other) => super.neq(_comparisonOperand(other));

  /// Less-than using the hardware encodings in [mapping].
  @override
  Logic lt(dynamic other) => super.lt(_comparisonOperand(other));

  /// Less-than-or-equal using the hardware encodings in [mapping].
  @override
  Logic lte(dynamic other) => super.lte(_comparisonOperand(other));

  /// Greater-than using the hardware encodings in [mapping].
  @override
  Logic gt(dynamic other) => super.gt(_comparisonOperand(other));

  /// Greater-than-or-equal using the hardware encodings in [mapping].
  @override
  Logic gte(dynamic other) => super.gte(_comparisonOperand(other));

  /// Greater-than using the hardware encodings in [mapping].
  @override
  Logic operator >(dynamic other) => gt(other);

  /// Greater-than-or-equal using the hardware encodings in [mapping].
  @override
  Logic operator >=(dynamic other) => gte(other);

  /// Injects either a [T] value or a standard logic value into this signal.
  @override
  void inject(dynamic val, {bool fill = false}) {
    if (val is T) {
      if (fill) {
        throw ArgumentError.value(
            fill, 'fill', 'Enum values cannot be used as a fill pattern.');
      }
      if (!mapping.containsKey(val)) {
        throw ArgumentError.value(val, 'val', 'Not present in the mapping.');
      }
      super.inject(mapping[val]);
    } else {
      super.inject(val, fill: fill);
    }
  }

  /// Updates the signal value, accepting either [T] or standard logic values.
  @override
  void put(dynamic val, {bool fill = false}) {
    if (val is T) {
      if (fill) {
        throw ArgumentError.value(
            fill, 'fill', 'Enum values cannot be used as a fill pattern.');
      }

      if (!mapping.containsKey(val)) {
        throw ArgumentError.value(val, 'val', 'Not present in the mapping.');
      }

      // we just checked that mapping contains the key
      // ignore: unnecessary_null_checks
      super.put(mapping[val]!);
    } else {
      super.put(val, fill: fill);
    }
  }

  /// Whether [other] has the same enum type and hardware encoding.
  bool isEquivalentTypeTo(Logic other) {
    if (other is! LogicEnum<T>) {
      return false;
    }

    final mappingsEqual = const MapEquality<Enum, LogicValue>().equals(
      mapping,
      other.mapping,
    );

    if (!mappingsEqual) {
      return false;
    }

    return true;
  }

  /// Whether every enum value from [other] is representable by this signal.
  @internal
  bool canAcceptValuesFrom(LogicEnum other) =>
      other is LogicEnum<T> &&
      width == other.width &&
      other.mapping.entries.every((entry) => mapping[entry.key] == entry.value);

  /// Creates an unconnected, driveable enum signal, without copying its value.
  ///
  /// Preserves [T], [mapping], [width], [definitionName], and
  /// [reserveDefinitionName], even when this signal is driven by a constant.
  @override
  LogicEnum<T> clone({String? name}) => LogicEnum<T>.withMapping(
        mapping,
        width: width,
        name: name ?? this.name,
        naming: Naming.chooseCloneNaming(
          originalName: this.name,
          newName: name,
          originalNaming: naming,
          newNaming: null,
        ),
        definitionName: definitionName,
        reserveDefinitionName: reserveDefinitionName,
      );
}

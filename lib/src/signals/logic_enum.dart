part of 'signals.dart';

// TODO: what if you assign between LogicEnums of the same T, but different mappings?
//  - by default, throw an exception if assignment between enums of different mappings?
// TODO: should we support enum ports? then where does the typedef live?

//TODO: do we need to support arrays of enums?

//TODO: how do you define a constant version of an enum?

class LogicEnum<T extends Enum> extends LogicDef {
  //TODO: if a `put` has an illegal value prop X

  late final Map<T, LogicValue> mapping;
  // late final List<T> values;

  //TODO better exceptions throughout

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
    for (final MapEntry(key: key, value: computedValue)
        in computedMapping.entries) {
      if (mapping[key] is int) {
        if (computedValue.toInt() != mapping[key]) {
          throw ArgumentError(
              'Mapping value for $key is not equal to the original int value.'
              ' Computed: $computedValue, Original: ${mapping[key]}');
        }
      }

      if (mapping[key] is BigInt) {
        if (computedValue.toBigInt() != mapping[key]) {
          throw ArgumentError(
              'Mapping value for $key is not equal to the original BigInt value.'
              ' Computed: $computedValue, Original: ${mapping[key]}');
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
      width = LogicValue.ofInt(mapping.length, 32).clog2().toInt();

      if (mapping.values.toSet().length != mapping.values.length) {
        throw ArgumentError(
            'Mapping values must be unique, but found duplicates: $mapping');
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

  /// TODO
  ///
  /// If [reserveDefinitionName] is true, then the enum names will be reserved
  /// as well.
  LogicEnum.withMapping(
    Map<T, dynamic> mapping, {
    int? width,
    super.name,
    super.naming,
    String? definitionName,
    super.reserveDefinitionName,
  }) : super(
            width: _computeWidth(requestedWidth: width, mapping: mapping),
            definitionName: definitionName ??
                Naming.validatedName(T.toString(),
                    reserveName: reserveDefinitionName)) {
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

  LogicEnum(List<T> values,
      {int? width,
      String? name,
      Naming? naming,
      String? definitionName,
      bool reserveDefinitionName = false})
      : this.withMapping(
            Map.fromEntries(
                values.mapIndexed((index, value) => MapEntry(value, index))),
            width: width,
            name: name,
            naming: naming,
            definitionName: definitionName,
            reserveDefinitionName: reserveDefinitionName);

  // TODO: do we really need to track this isConst?
  bool _isConst = false;
  bool get isConst => _isConst;

  /// Drives this [LogicEnum] with a constant value matching the enum [value].
  void getsEnum(T value) {
    if (!mapping.containsKey(value)) {
      //TODO exception
      throw Exception('Value $value is not mapped in $mapping for enum $T.');
    }
    gets(Const(mapping[value]));
  }

  @override
  void gets(Logic other) {
    if (other is Const) {
      if (!mapping.containsValue(other.value)) {
        throw Exception(
            'Value ${other.value} is not mapped in $mapping for enum $T.');
      }

      _isConst = true;
    }

    super.gets(other);
  }

  @override
  void put(dynamic val, {bool fill = false}) {
    if (val is T) {
      if (fill) {
        throw Exception(); //TODO
      }

      if (!mapping.containsKey(val)) {
        throw Exception('Value $val is not mapped in $mapping.');
      }

      // ignore: unnecessary_null_checks
      super.put(mapping[val]!);
    } else {
      super.put(val, fill: fill);
    }
  }

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

  @override
  LogicEnum<T> clone({String? name}) => LogicEnum<T>.withMapping(mapping,
      width: width,
      name: name ?? this.name,
      naming:
          naming, //TODO: use same mechanism as Logic for naming determination
      definitionName: definitionName,
      reserveDefinitionName: reserveDefinitionName);
}

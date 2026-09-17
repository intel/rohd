// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// Definition of an array of `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// A multi-dimensional array structure of independent [Logic]s.
///
/// This is the ordinary [Logic]-leaf specialization of [TypedLogicArray]. It
/// has the same construction, port, clone, and naming API as the historical
/// `LogicArray` type.
class LogicArray extends TypedLogicArray<Logic, LogicValue> {
  /// Creates an array with specified [dimensions] and [elementWidth] named
  /// [name].
  ///
  /// [numUnpackedDimensions] is a [Synthesizer] hint. When it is greater than
  /// zero, that many outermost dimensions are emitted as unpacked dimensions
  /// in SystemVerilog. It has no effect on simulation behavior.
  factory LogicArray(List<int> dimensions, int elementWidth,
          {String? name, int numUnpackedDimensions = 0, Naming? naming}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: Logic.new,
          logicArrayBuilder: LogicArray.new,
          isNet: false);

  /// Creates an array of [LogicNet]s with [dimensions] and [elementWidth]
  /// named [name].
  ///
  /// [numUnpackedDimensions] has the same synthesis-only meaning as in
  /// [LogicArray].
  factory LogicArray.net(List<int> dimensions, int elementWidth,
          {String? name, int numUnpackedDimensions = 0, Naming? naming}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: LogicNet.new,
          logicArrayBuilder: LogicArray.net,
          isNet: true);

  LogicArray._(List<Logic> elements,
      {required super.dimensions,
      required super.elementWidth,
      required super.numUnpackedDimensions,
      required super.name,
      required super.naming,
      required bool isNet})
      : super._structured(
          elements,
          ({name}) => isNet
              ? LogicNet(name: name, width: elementWidth)
              : Logic(name: name, width: elementWidth),
          valueCodec: LogicValueCodec.logicValue,
          isNet: isNet,
        );

  factory LogicArray._factory(List<int> dimensions, int elementWidth,
          {required String? name,
          required int numUnpackedDimensions,
          required Naming? naming,
          required bool isNet,
          required Logic Function({int width, Naming naming, String name})
              logicBuilder,
          required LogicArray Function(List<int> nextDimensions, int width,
                  {int numUnpackedDimensions, String name})
              logicArrayBuilder}) =>
      BaseLogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: logicBuilder,
          logicArrayBuilder: logicArrayBuilder,
          arrayBuilder: LogicArray._,
          isNet: isNet) as LogicArray;

  @override
  LogicValueArray get value => LogicValueArray.fromFlat(
        dimensions,
        arrayElements.map((element) => element.value),
        elementWidth: elementWidth,
      );

  @override
  LogicValueArray? get previousValue =>
      arrayElements.any((element) => element.previousValue == null)
          ? null
          : LogicValueArray.fromFlat(
              dimensions,
              arrayElements.map((element) => element.previousValue!),
              elementWidth: elementWidth,
            );

  @override

  /// Creates a [LogicArray] with the same dimensions, element width, unpacked
  /// dimensions, net type, and name as this array unless [name] is provided.
  LogicArray clone({String? name}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name ?? this.name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: Naming.chooseCloneNaming(
              originalName: this.name,
              newName: name,
              originalNaming: naming,
              newNaming: null),
          logicBuilder: isNet ? LogicNet.new : Logic.new,
          logicArrayBuilder: isNet ? LogicArray.net : LogicArray.new,
          isNet: isNet);

  @override

  /// Clones this array with [name] and connects the clone to this array.
  LogicArray named(String name, {Naming? naming}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: Naming.chooseCloneNaming(
              originalName: this.name,
              newName: name,
              originalNaming: this.naming,
              newNaming: naming),
          logicBuilder: isNet ? LogicNet.new : Logic.new,
          logicArrayBuilder: isNet ? LogicArray.net : LogicArray.new,
          isNet: isNet)
        ..gets(this);

  @override
  Iterable<LogicArray> get majorSlices {
    if (dimensions.length < 2) {
      throw StateError('majorSlices requires at least two dimensions.');
    }
    return elements.cast<LogicArray>();
  }

  /// Creates an array port with a convenient constructor signature.
  ///
  /// The port uses mergeable naming so repeated interface connections retain a
  /// single SystemVerilog port declaration.
  factory LogicArray.port(String name,
      [List<int> dimensions = const [1],
      int elementWidth = 1,
      int numUnpackedDimensions = 0]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicArray(dimensions, elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
        name: name,
        naming: Naming.mergeable);
  }

  /// Creates a net array port with a convenient constructor signature.
  ///
  /// The port uses mergeable naming so repeated interface connections retain a
  /// single SystemVerilog port declaration.
  factory LogicArray.netPort(String name,
      [List<int> dimensions = const [1],
      int elementWidth = 1,
      int numUnpackedDimensions = 0]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicArray.net(dimensions, elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
        name: name,
        naming: Naming.mergeable);
  }
}

// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_structure.dart
// Definition of a structure containing multiple `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of signals;

class LogicStructure implements Logic {
  /// All elements of this structure.
  @override
  late final List<Logic> elements = UnmodifiableListView(_elements);
  final List<Logic> _elements = [];

  /// Packs all [elements] into one flattened bus.
  late final Logic packed = elements
      .map((e) {
        if (e is LogicStructure) {
          return e.packed;
        } else {
          return e;
        }
      })
      .toList(growable: false)
      .rswizzle();

  @override
  final String name;

  /// An internal counter for encouraging unique naming of unnamed signals.
  static int _structIdx = 0;

  /// Creates a new [LogicStructure] with [elements] as elements.
  ///
  /// None of the [elements] can already be members of another [LogicStructure].
  LogicStructure(Iterable<Logic> elements, {String? name})
      : name = (name == null || name.isEmpty)
            ? 'st${_structIdx++}'
            : Sanitizer.sanitizeSV(name) {
    _elements
      ..addAll(elements)
      ..forEach((element) {
        if (element._parentStructure != null) {
          throw LogicConstructionException(
              '$element already is a member of a structure'
              ' ${element._parentStructure}.');
        }

        element._parentStructure = this;
      });
  }

  @override
  String get structureName {
    if (parentStructure != null) {
      if (isArrayMember) {
        return '${parentStructure!.structureName}[${arrayIndex!}]';
      } else {
        return '${parentStructure!.structureName}.$name';
      }
    } else {
      return name;
    }
  }

  @override
  int? get arrayIndex => _arrayIndex;

  @override
  int? _arrayIndex;

  @override
  bool get isArrayMember => parentStructure is LogicArray;

  //TODO: delete this crap
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////

  @override
  void put(dynamic val, {bool fill = false}) {
    final logicVal = LogicValue.of(val, fill: fill, width: width);

    var index = 0;
    for (final element in leafElements) {
      element.put(logicVal.getRange(index, index + element.width));
      index += element.width;
    }
  }

  @override
  void inject(dynamic val, {bool fill = false}) {
    final logicVal = LogicValue.of(val, fill: fill, width: width);

    var index = 0;
    for (final element in leafElements) {
      element.inject(logicVal.getRange(index, index + element.width));
      index += element.width;
    }
  }

  @override
  void gets(Logic other) {
    if (other.width != width) {
      throw SignalWidthMismatchException(other, width);
    }

    var index = 0;
    for (final element in leafElements) {
      element <= other.getRange(index, index + element.width);

      index += element.width;
    }
  }

  @override
  Conditional operator <(dynamic other) {
    final otherLogic = other is Logic ? other : Const(other, width: width);

    if (otherLogic.width != width) {
      throw SignalWidthMismatchException(otherLogic, width);
    }

    final conditionalAssigns = <Conditional>[];

    var index = 0;
    for (final element in leafElements) {
      conditionalAssigns
          .add(element < otherLogic.getRange(index, index + element.width));
      index += element.width;
    }

    return ConditionalGroup(conditionalAssigns);
  }

  /// A list of all leaf-level elements at the deepest hierarchy of this
  /// structure provided in index order.
  late final List<Logic> leafElements =
      UnmodifiableListView(_calculateLeafElements());

  /// Compute the list of all leaf elements, to be cached in [leafElements].
  List<Logic> _calculateLeafElements() {
    final leaves = <Logic>[];
    for (final element in elements) {
      if (element is LogicStructure) {
        leaves.addAll(element._calculateLeafElements());
      } else {
        leaves.add(element);
      }
    }
    return leaves;
  }

  @override
  void operator <=(Logic other) => gets(other);

  @override
  Logic operator [](dynamic index) => packed[index];

  @override
  Logic getRange(int startIndex, [int? endIndex]) {
    endIndex ??= width;

    final modifiedStartIndex =
        IndexUtilities.wrapIndex(startIndex, width, allowWidth: true);
    final modifiedEndIndex =
        IndexUtilities.wrapIndex(endIndex, width, allowWidth: true);

    IndexUtilities.validateRange(modifiedStartIndex, modifiedEndIndex);

    //TODO: test edge cases here

    // grab all elements that fall in this range, keeping track of the offset
    final matchingElements = <Logic>[];

    final requestedWidth = modifiedEndIndex - modifiedStartIndex;

    var index = 0;
    for (final element in leafElements) {
      // if the *start* or *end* of `element` is within [startIndex, endIndex],
      // then we have to include it in `matchingElements`
      final elementStart = index;
      final elementEnd = index + element.width;

      final elementInRange = ((elementStart >= modifiedStartIndex) &&
              (elementStart < modifiedEndIndex)) ||
          ((elementEnd > modifiedStartIndex) &&
              (elementEnd <= modifiedEndIndex));

      if (elementInRange) {
        // figure out the subset of `element` that needs to be included
        final elementStartGrab = max(elementStart, modifiedStartIndex) - index;
        final elementEndGrab = min(elementEnd, modifiedEndIndex) - index;

        matchingElements
            .add(element.getRange(elementStartGrab, elementEndGrab));
      }

      index += element.width;
    }

    assert(!(matchingElements.isEmpty && requestedWidth != 0),
        'If the requested width is not 0, expect to get some matches.');

    return matchingElements.rswizzle();
  }

  @override
  Logic slice(int endIndex, int startIndex) {
    final modifiedStartIndex = IndexUtilities.wrapIndex(startIndex, width);
    final modifiedEndIndex = IndexUtilities.wrapIndex(endIndex, width);

    if (modifiedStartIndex <= modifiedEndIndex) {
      return getRange(modifiedStartIndex, modifiedEndIndex + 1);
    } else {
      //TODO: special test for this reversed case, make sure SV looks right
      return getRange(modifiedEndIndex, modifiedStartIndex + 1).reversed;
    }
  }

  //TODO: don't make these operate on per-element, just pack the whole thing and do it?

  /// Increments each element of [elements] using [Logic.incr].
  @override
  Conditional incr(
          {Logic Function(Logic p1) s = Logic._nopS, dynamic val = 1}) =>
      ConditionalGroup([
        for (final element in elements) element.incr(s: s, val: val),
      ]);

  /// Decrements each element of [elements] using [Logic.decr].
  @override
  Conditional decr(
          {Logic Function(Logic p1) s = Logic._nopS, dynamic val = 1}) =>
      ConditionalGroup([
        for (final element in elements) element.decr(s: s, val: val),
      ]);

  /// Divide-assigns each element of [elements] using [Logic.divAssign].
  @override
  Conditional divAssign(
          {Logic Function(Logic p1) s = Logic._nopS, dynamic val}) =>
      ConditionalGroup([
        for (final element in elements) element.divAssign(s: s, val: val),
      ]);

  /// Multiply-assigns each element of [elements] using [Logic.mulAssign].
  @override
  Conditional mulAssign(
          {Logic Function(Logic p1) s = Logic._nopS, dynamic val}) =>
      ConditionalGroup([
        for (final element in elements) element.mulAssign(s: s, val: val),
      ]);

  @override
  late final Iterable<Logic> dstConnections = [
    for (final element in elements) ...element.dstConnections
  ];

  //TODO: is this safe to have a separate tracking here?
  Module? _parentModule;

  @override
  Module? get parentModule => _parentModule;

  @protected
  @override
  set parentModule(Module? newParentModule) {
    _parentModule = newParentModule;
    for (final element in elements) {
      element.parentModule = newParentModule;
    }
  }

  @override
  LogicStructure? get parentStructure => _parentStructure;

  @override
  LogicStructure? _parentStructure;

  @override
  bool get isInput => parentModule?.isInput(this) ?? false;

  @override
  bool get isOutput => parentModule?.isOutput(this) ?? false;

  @override
  bool get isPort => isInput || isOutput;

  @override
  void makeUnassignable() {
    for (final element in elements) {
      element.makeUnassignable();
    }
  }

  /// A [LogicStructure] never has a direct source driving it, only its
  /// [elements] do, so always returns `null`.
  @override
  Logic? get srcConnection => null;

  @override
  LogicValue get value => packed.value;

  @override
  late final int width = elements.isEmpty
      ? 0
      : elements.map((e) => e.width).reduce((w1, w2) => w1 + w2);

  // TODO: withset should return a similar structure?? special case for array also?
  @override
  Logic withSet(int startIndex, Logic update) =>
      packed.withSet(startIndex, update);

  /////////////////////////////////////////////////
  /////////////////////////////////////////////////
  /////////////////////////////////////////////////
  /////////////////////////////////////////////////

  @override
  Logic operator ~() => ~packed;

  @override
  Logic operator &(Logic other) => packed & other;

  @override
  Logic operator |(Logic other) => packed | other;

  @override
  Logic operator ^(Logic other) => packed ^ other;

  @override
  Logic operator *(dynamic other) => packed * other;

  @override
  Logic operator +(dynamic other) => packed + other;

  @override
  Logic operator -(dynamic other) => packed - other;

  @override
  Logic operator /(dynamic other) => packed / other;

  @override
  Logic operator %(dynamic other) => packed % other;

  @override
  Logic pow(dynamic exponent) => packed.pow(exponent);

  @override
  Logic operator <<(dynamic other) => packed << other;

  @override
  Logic operator >(dynamic other) => packed > other;

  @override
  Logic operator >=(dynamic other) => packed >= other;

  @override
  Logic operator >>(dynamic other) => packed >> other;

  @override
  Logic operator >>>(dynamic other) => packed >>> other;

  @override
  Logic and() => packed.and();

  @override
  Logic or() => packed.or();

  @override
  Logic xor() => packed.xor();

  @Deprecated('Use `value` instead.'
      '  Check `width` separately to confirm single-bit.')
  @override
  LogicValue get bit => packed.bit;

  @override
  Stream<LogicValueChanged> get changed => packed.changed;

  @override
  Logic eq(dynamic other) => packed.eq(other);

  @override
  Logic neq(dynamic other) => packed.neq(other);

  @override
  SynchronousEmitter<LogicValueChanged> get glitch => packed.glitch;

  @override
  Logic gt(dynamic other) => packed.gt(other);

  @override
  Logic gte(dynamic other) => packed.gte(other);

  @override
  Logic lt(dynamic other) => packed.lt(other);

  @override
  Logic lte(dynamic other) => packed.lte(other);

  @Deprecated('Use value.isValid instead.')
  @override
  bool hasValidValue() => packed.hasValidValue();

  @Deprecated('Use value.isFloating instead.')
  @override
  bool isFloating() => packed.isFloating();

  @override
  Logic isIn(List<dynamic> list) => packed.isIn(list);

  @override
  Stream<LogicValueChanged> get negedge => packed.negedge;

  @override
  Stream<LogicValueChanged> get posedge => packed.posedge;

  @override
  Future<LogicValueChanged> get nextChanged => packed.nextChanged;

  @override
  Future<LogicValueChanged> get nextNegedge => packed.nextNegedge;

  @override
  Future<LogicValueChanged> get nextPosedge => packed.nextPosedge;

  @override
  Logic replicate(int multiplier) => packed.replicate(multiplier);

  // TODO: reversed should do something more clever? reverse each individual one and swizzle?
  @override
  Logic get reversed => packed.reversed;

  @override
  Logic signExtend(int newWidth) => packed.signExtend(newWidth);

  @override
  Logic zeroExtend(int newWidth) => packed.zeroExtend(newWidth);

  @override
  // ignore: deprecated_member_use_from_same_package
  BigInt get valueBigInt => packed.valueBigInt;

  @override
  // ignore: deprecated_member_use_from_same_package
  int get valueInt => packed.valueInt;

  /////////////////////////////////////////////
  /////////////////////////////////////////////
  /////////////////////////////////////////////

  @override
  Logic? get _srcConnection => throw UnsupportedError('Delegated to elements');

  @override
  set _srcConnection(Logic? srcConnection) {
    throw UnsupportedError('Delegated to elements');
  }

  @override
  bool get _unassignable => throw UnsupportedError('Delegated to elements');

  @override
  set _unassignable(bool unassignable) {
    throw UnsupportedError('Delegated to elements');
  }

  @override
  _Wire get _wire => throw UnsupportedError('Delegated to elements');

  @override
  set _wire(_Wire wire) {
    throw UnsupportedError('Delegated to elements');
  }

  @override
  void _assertConnectable(Logic other) {
    throw UnsupportedError('Delegated to elements');
  }

  @override
  void _connect(Logic other) {
    throw UnsupportedError('Delegated to elements');
  }

  @override
  Set<Logic> get _dstConnections =>
      throw UnsupportedError('Delegated to elements');

  @override
  void _registerConnection(Logic dstConnection) {
    throw UnsupportedError('Delegated to elements');
  }

  @override
  void _updateWire(_Wire newWire) {
    throw UnsupportedError('Delegated to elements');
  }
}

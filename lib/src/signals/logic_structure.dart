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
  LogicStructure(Iterable<Logic> elements, {String? name})
      : name = (name == null || name.isEmpty)
            ? 'st${_structIdx++}'
            : Sanitizer.sanitizeSV(name) {
    //TODO: make sure no components already have a parentComponent
    // but do we care?
    _elements
      ..addAll(elements)
      ..forEach((element) {
        element._parentStructure = this;
      });
  }

  //TODO
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

  int? _arrayIndex;
  int? get arrayIndex => _arrayIndex;

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
    for (final element in elements) {
      element.put(logicVal.getRange(index, index + element.width));
      index += element.width;
    }
  }

  @override
  void inject(dynamic val, {bool fill = false}) {
    final logicVal = LogicValue.of(val, fill: fill, width: width);

    var index = 0;
    for (final element in elements) {
      element.inject(logicVal.getRange(index, index + element.width));
      index += element.width;
    }
  }

  @override
  Conditional operator <(dynamic other) {
    final otherLogic = other is Logic ? other : Const(other, width: width);

    if (otherLogic.width != width) {
      throw PortWidthMismatchException(otherLogic, width);
    }

    final conditionalAssigns = <Conditional>[];

    var index = 0;
    for (final element in elements) {
      //TODO: same as `gets`, iterate if element is array?
      conditionalAssigns
          .add(element < otherLogic.getRange(index, index + element.width));
      index += element.width;
    }

    return ConditionalGroup(conditionalAssigns);
  }

  //TODO
  late final List<Logic> leafElements =
      UnmodifiableListView(_calculateLeafElements());

  //TODO: cache this
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
  void gets(Logic other) {
    if (other.width != width) {
      throw PortWidthMismatchException(other, width);
    }

    var index = 0;
    for (final element in leafElements) {
      element <= other.getRange(index, index + element.width);

      index += element.width;
    }
  }

  @override
  void operator <=(Logic other) => gets(other);

  @override
  Logic operator [](dynamic index) => packed[index];

  @override
  Logic getRange(int startIndex, [int? endIndex]) {
    endIndex ??= width;

    //TODO: do math for modified indices!

    //TODO: do range checks

    //TODO: test edge cases here

    // grab all elements that fall in this range, keeping track of the offset
    final matchingElements = <Logic>[];

    final requestedWidth = endIndex - startIndex;

    var index = 0;
    for (final element in leafElements) {
      // if the *start* or *end* of `element` is within [startIndex, endIndex],
      // then we have to include it in `matchingElements`
      final elementStart = index;
      final elementEnd = index + element.width;

      final elementInRange =
          ((elementStart >= startIndex) && (elementStart < endIndex)) ||
              ((elementEnd > startIndex) && (elementEnd <= endIndex));

      if (elementInRange) {
        // figure out the subset of `element` that needs to be included
        final elementStartGrab = max(elementStart, startIndex) - index;
        final elementEndGrab = min(elementEnd, endIndex) - index;

        matchingElements
            .add(element.getRange(elementStartGrab, elementEndGrab));
      }

      index += element.width;
    }

    assert(!(matchingElements.isEmpty && requestedWidth != 0),
        'If the requested width is not 0, expect to get some matches.');

    return matchingElements.swizzle();
  }

  @override
  Logic slice(int endIndex, int startIndex) =>
      packed.slice(endIndex, startIndex);

  //TODO: don't make these operate on per-element, just pack the whole thing and do it?

  /// Increments each element of [elements] using [Logic.incr].
  @override
  Conditional incr(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val = 1}) =>
      ConditionalGroup([
        for (final element in elements) element.incr(s: s, val: val),
      ]);

  /// Decrements each element of [elements] using [Logic.decr].
  @override
  Conditional decr(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val = 1}) =>
      ConditionalGroup([
        for (final element in elements) element.decr(s: s, val: val),
      ]);

  /// Divide-assigns each element of [elements] using [Logic.divAssign].
  @override
  Conditional divAssign(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val}) =>
      ConditionalGroup([
        for (final element in elements) element.divAssign(s: s, val: val),
      ]);

  /// Multiply-assigns each element of [elements] using [Logic.mulAssign].
  @override
  Conditional mulAssign(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val}) =>
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

  //TODO: to track naming
  @override
  LogicStructure? get parentStructure => _parentStructure;
  LogicStructure? _parentStructure;

  @override
  bool get isInput => parentModule?.isInput(this) ?? false;

  @override
  // TODO: implement isOutput
  bool get isOutput => parentModule?.isOutput(this) ?? false;

  @override
  // TODO: implement isPort
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

  @override
  bool hasValidValue() => packed.hasValidValue();

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

// Copyright (C) 2023-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_structure.dart
// Definition of a structure containing multiple `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Collects a group of [Logic] signals into one entity which can be manipulated
/// in a similar way as an individual [Logic].
class LogicStructure implements Logic {
  /// All elements of this structure.
  @override
  late final List<Logic> elements = UnmodifiableListView(_elements);
  final List<Logic> _elements = [];

  /// Packs all [elements] into one flattened [Logic] bus.
  @override
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

  @override
  Naming get naming => Naming.unnamed;

  /// Creates a new [LogicStructure] with [elements] as elements.
  ///
  /// None of the [elements] can already be members of another [LogicStructure].
  LogicStructure(Iterable<Logic> elements, {String? name})
      : name = Naming.chooseName(name, null, nullStarter: 'st') {
    _elements
      ..addAll(elements)
      ..forEach((element) {
        if (element.parentStructure != null) {
          throw LogicConstructionException(
              '$element already is a member of a structure'
              ' ${element.parentStructure}.');
        }

        element._parentStructure = this;
      });
  }

  @override
  LogicStructure _clone({String? name, Naming? naming}) =>
      // naming is not used for LogicStructure
      LogicStructure(elements.map((e) => e.clone(name: e.name)),
          name: name ?? this.name);

  /// Creates a new [LogicStructure] with the same structure as `this` and
  /// [clone]d [elements], optionally with the provided [name].
  ///
  /// It is expected that any implementation will override this in a way that
  /// returns the same type as itself.
  @override
  @mustBeOverridden
  LogicStructure clone({String? name}) => _clone(name: name);

  /// Makes a [clone], optionally with the specified [name], then assigns it to
  /// be driven by `this`.
  ///
  /// The [naming] argument will not have any effect on a generic
  /// [LogicStructure], but behavior may be overridden by implementers.
  ///
  /// This is a useful utility for naming the result of some hardware
  /// construction without separately declaring a new named signal and then
  /// assigning.
  @override
  LogicStructure named(String name, {Naming? naming}) =>
      clone(name: name)..gets(this);

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
    Simulator.injectAction(() => put(val, fill: fill));
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
        leaves.addAll(element.leafElements);
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

    // grab all elements that fall in this range, keeping track of the offset
    final matchingElements = <Logic>[];

    final requestedWidth = modifiedEndIndex - modifiedStartIndex;

    var index = 0;
    for (final element in leafElements) {
      // if the *start* or *end* of `element` is within [startIndex, endIndex],
      // then we have to include it in `matchingElements`
      final elementStart = index;
      final elementEnd = index + element.width;

      // if the element is even partially within the range, then include it
      // OR, if it is wholly contained within the range, include it
      final elementInRange =
          // end is within the element
          (modifiedEndIndex > elementStart && modifiedEndIndex < elementEnd) ||
              // start is within the element
              (modifiedStartIndex >= elementStart &&
                  modifiedStartIndex < elementEnd) ||
              // element is fully contained
              (modifiedEndIndex >= elementEnd &&
                  modifiedStartIndex <= elementStart);

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
      return getRange(modifiedEndIndex, modifiedStartIndex + 1).reversed;
    }
  }

  /// Increments each element of [elements] using [Logic.incr].
  @override
  Conditional incr({Logic Function(Logic p1)? s, dynamic val = 1}) =>
      s == null ? (this < this + val) : (s(this) < s(this) + val);

  /// Decrements each element of [elements] using [Logic.decr].
  @override
  Conditional decr({Logic Function(Logic p1)? s, dynamic val = 1}) =>
      s == null ? (this < this - val) : (s(this) < s(this) - val);

  /// Divide-assigns each element of [elements] using [Logic.divAssign].
  @override
  Conditional divAssign(dynamic val, {Logic Function(Logic p1)? s}) =>
      s == null ? (this < this / val) : (s(this) < s(this) / val);

  /// Multiply-assigns each element of [elements] using [Logic.mulAssign].
  @override
  Conditional mulAssign(dynamic val, {Logic Function(Logic p1)? s}) =>
      s == null ? (this < this * val) : (s(this) < s(this) * val);

  @override
  Iterable<Logic> get dstConnections => {
        for (final element in elements) ...element.dstConnections
      }.toList(growable: false);

  @override
  Module? get parentModule => _parentModule;
  @override
  Module? _parentModule;

  @internal
  @override
  set parentModule(Module? newParentModule) {
    assert(_parentModule == null || _parentModule == newParentModule,
        'Should only set parent module once.');

    _parentModule = newParentModule;
  }

  /// Performs a recursive call of setting [parentModule] on all of [elements]
  /// and their [elements] for any sub-[LogicStructure]s.
  ///
  /// This should *only* be called by [Module.build].  It is used to optimize
  /// search.
  @internal
  void setAllParentModule(Module? newParentModule) {
    assert(_parentModule == null || _parentModule == newParentModule,
        'Should only set parent module once.');

    parentModule = newParentModule;
    for (final element in elements) {
      if (element is LogicStructure) {
        element.setAllParentModule(newParentModule);
      }
      element.parentModule = newParentModule;
    }
  }

  @override
  LogicStructure? get parentStructure => _parentStructure;

  @override
  LogicStructure? _parentStructure;

  @override
  late final bool isInput = parentModule?.isInput(this) ?? false;

  @override
  late final bool isOutput = parentModule?.isOutput(this) ?? false;

  @override
  late final bool isInOut = parentModule?.isInOut(this) ?? false;

  @override
  late final bool isPort = isInput || isOutput || isInOut;

  @override
  void makeUnassignable({String? reason}) {
    for (final element in elements) {
      element.makeUnassignable(reason: reason);
    }
  }

  /// A [LogicStructure] never has a direct source driving it, only its
  /// [elements] do, so always returns `null`.
  @override
  Logic? get srcConnection => null;

  @override
  LogicValue get value =>
      elements.map((e) => e.value).toList(growable: false).rswizzle();

  @override
  LogicValue? get previousValue => elements.any((e) => e.previousValue == null)
      ? null
      : elements
          .map((e) => e.previousValue!)
          .toList(growable: false)
          .rswizzle();

  @override
  late final int width = elements.map((e) => e.width).sum;

  @override
  Logic withSet(int startIndex, Logic update) {
    final endIndex = startIndex + update.width;

    if (endIndex > width) {
      throw RangeError('Width of update $update at startIndex $startIndex would'
          ' overrun the width of the original ($width).');
    }

    if (startIndex < 0) {
      throw RangeError(
          'Start index must be greater than zero but was $startIndex');
    }

    final newWithSet = clone();

    var index = 0;
    for (var i = 0; i < leafElements.length; i++) {
      final newElement = newWithSet.leafElements[i];
      final element = leafElements[i];

      final elementWidth = element.width;

      // if the *start* or *end* of `element` is within [startIndex, endIndex],
      // then we have to include it in `matchingElements`
      final elementStart = index;
      final elementEnd = index + elementWidth;

      final elementInRange =
          ((elementStart >= startIndex) && (elementStart < endIndex)) ||
              ((elementEnd > startIndex) && (elementEnd <= endIndex));

      if (elementInRange) {
        newElement <=
            element.withSet(
                max(startIndex - index, 0),
                update.getRange(
                  max(index - startIndex, 0),
                  min(index - startIndex + elementWidth, update.width),
                ));
      } else {
        newElement <= element;
      }

      index += element.width;
    }

    return newWithSet;
  }

  @override
  void assignSubset(List<Logic> updatedSubset, {int start = 0}) {
    if (updatedSubset.length > elements.length - start) {
      throw SignalWidthMismatchException.forWidthOverflow(
          updatedSubset.length, elements.length - start);
    }

    // Assign Logic array from `start` index to `start+updatedSubset.length`
    for (var i = 0; i < updatedSubset.length; i++) {
      elements[start + i] <= updatedSubset[i];
    }
  }

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
  // Can rely on `packed` here because it must be 1 bit.
  LogicValue get bit => packed.bit;

  @override
  late final Stream<LogicValueChanged> changed = _internalPacked.changed;

  /// An internal version of [packed] for instrumentation operations on this
  /// [LogicStructure].
  late final _internalPacked = _generateInternalPacked();

  /// Generates and subscribes to be stored lazily into [_internalPacked].
  Logic _generateInternalPacked() {
    final internalPacked = Logic(width: width)..put(value);

    void updateInternalPacked() {
      internalPacked.put(value);
    }

    for (final element in elements) {
      element.glitch.listen((args) {
        updateInternalPacked();
      });
    }

    return internalPacked;
  }

  @override
  Logic eq(dynamic other) => packed.eq(other);

  @override
  Logic neq(dynamic other) => packed.neq(other);

  @override
  late final SynchronousEmitter<LogicValueChanged> glitch =
      _internalPacked.glitch;

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
  bool hasValidValue() => value.isValid;

  @Deprecated('Use value.isFloating instead.')
  @override
  bool isFloating() => value.isFloating;

  @override
  Logic isIn(List<dynamic> list) => packed.isIn(list);

  @override
  // Can rely on `packed` here because it must be 1 bit.
  Stream<LogicValueChanged> get negedge => packed.negedge;

  @override
  // Can rely on `packed` here because it must be 1 bit.
  Stream<LogicValueChanged> get posedge => packed.posedge;

  @override
  Future<LogicValueChanged> get nextChanged => changed.first;

  @override
  // Can rely on `packed` here because it must be 1 bit.
  Future<LogicValueChanged> get nextNegedge => packed.nextNegedge;

  @override
  // Can rely on `packed` here because it must be 1 bit.
  Future<LogicValueChanged> get nextPosedge => packed.nextPosedge;

  @override
  Logic replicate(int multiplier) => packed.replicate(multiplier);

  @override
  late final Logic reversed = packed.reversed;

  @override
  Logic abs() => packed.abs();

  @override
  Logic signExtend(int newWidth) => packed.signExtend(newWidth);

  @override
  Logic zeroExtend(int newWidth) => packed.zeroExtend(newWidth);

  @Deprecated('Use `value` instead.'
      '  Check `width` separately to confirm single-bit.')
  @override
  BigInt get valueBigInt => value.toBigInt();

  @Deprecated('Use value.toInt() instead.')
  @override
  int get valueInt => value.toInt();

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

  @override
  Logic selectFrom(List<Logic> busList, {Logic? defaultValue}) =>
      packed.selectFrom(busList, defaultValue: defaultValue);

  @override
  bool get isNet => _isNet;
  late final bool _isNet = elements.every((e) => e.isNet);

  /// Indicates whether this structure or any of its elements [isNet].
  bool get hasNets => _hasNets;
  late final bool _hasNets =
      elements.any((e) => e.isNet || (e is LogicStructure && e.hasNets)) ||
          isNet;

  @override
  Iterable<Logic> get srcConnections => {
        for (final element in elements) ...element.srcConnections
      }.toList(growable: false);

  @override
  List<Logic> get _srcConnections => throw UnsupportedError('Unnecessary');

  @override
  LogicArray? get _subsetDriver => throw UnsupportedError('Unnecessary');

  @override
  set _subsetDriver(LogicArray? _) => throw UnsupportedError('Unnecessary');

  @override
  String? get _unassignableReason =>
      throw UnsupportedError('Delegated to elements');

  @override
  // ignore: unused_element
  set _unassignableReason(String? _) =>
      throw UnsupportedError('Delegated to elements');

  @override
  String toString() => 'LogicStructure(${super.toString()}): $name';
}

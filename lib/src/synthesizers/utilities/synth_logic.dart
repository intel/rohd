// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_logic.dart
// Definitions for signal representations during generation
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents a logic signal in the generated code within a module.
class SynthLogic {
  /// All [Logic]s represented, regardless of type.
  List<Logic> get logics => UnmodifiableListView([
        if (_reservedLogic != null) _reservedLogic!,
        if (_constLogic != null) _constLogic!,
        if (_renameableLogic != null) _renameableLogic!,
        ..._mergeableLogics,
        ..._unnamedLogics,
      ]);

  /// If this was merged and is now replaced by another, then this is non-null
  /// and points to it.
  SynthLogic? get replacement => _replacement?.replacement ?? _replacement;
  set replacement(SynthLogic? newReplacement) {
    _replacement?.replacement = newReplacement;
    _replacement = newReplacement;
  }

  /// The direct replacement of this [SynthLogic].
  SynthLogic? _replacement;

  /// The width of any/all of the [logics].
  int get width => logics.first.width;

  /// Indicates that this has a reserved name.
  bool get isReserved => _reservedLogic != null;

  /// The [Logic] whose name is reserved, if there is one.
  Logic? _reservedLogic;

  /// The [Logic] whose name is renameable, if there is one.
  Logic? _renameableLogic;

  /// A [LogicEnum] that is characteristic of any merged [LogicEnum]s into this.
  LogicEnum? get characteristicEnum => _firstEnum;

  /// The first [LogicEnum] merged into this [SynthLogic], if there is one.
  LogicEnum? _firstEnum;

  /// [Logic]s that are marked mergeable.
  final Set<Logic> _mergeableLogics = {};

  /// [Logic]s that are unnamed.
  final Set<Logic> _unnamedLogics = {};

  /// The [Logic] whose value represents a constant, if there is one.
  Const? _constLogic;

  /// Assignments should be eliminated rather than assign to `z`, so this
  /// indicates if this [SynthLogic] is actually pointing to a [Const] that
  /// is floating.
  bool get isFloatingConstant => _constLogic?.value.isFloating ?? false;

  /// Whether this represents a constant.
  bool get isConstant => _constLogic != null;

  /// Whether this represents a net.
  bool get isNet =>
      // can just look at the first since nets and non-nets cannot be merged
      logics.first.isNet || (isArray && (logics.first as LogicArray).isNet);

  /// Whether this represents an enum.
  bool get isEnum =>
      // can just look at the first since enums and non-enums cannot be merged
      logics.first is LogicEnum;

  /// If set, then this should never pick the constant as the name.
  bool get constNameDisallowed => _constNameDisallowed;
  bool _constNameDisallowed;

  /// Whether this signal should be declared.
  bool get needsDeclaration => !(isConstant && !_constNameDisallowed);

  /// Two [SynthLogic]s that are not [mergeable] cannot be merged with each
  /// other. If onlyt one of them is not [mergeable], it can adopt the elements
  /// from the other.
  bool get mergeable =>
      _reservedLogic == null && _constLogic == null && _renameableLogic == null;

  /// True only if this represents a [LogicArray].
  final bool isArray;

  /// The chosen name of this.
  ///
  /// Must call [pickName] before this is accessible.
  String get name {
    assert(_replacement == null,
        'If this has been replaced, then we should not be getting its name.');
    assert(isConstant || Sanitizer.isSanitary(_name!),
        'Signal names should be sanitary, but found $_name.');

    return _name!;
  }

  /// The name of this, if it has been picked.
  String? _name;

  /// Picks a [name].
  ///
  /// Must be called exactly once.
  void pickName(Uniquifier uniquifier) {
    assert(_name == null, 'Should only pick a name once.');

    _name = _findName(uniquifier);
    //TODO: dont allow merge after name picked?
  }

  /// Finds the best name from the collection of [Logic]s.
  String _findName(Uniquifier uniquifier) {
    // check for const
    if (isConstant) {
      if (!_constNameDisallowed) {
        if (isEnum) {
          // TODO: here is where we need to pring name of enum!
          // return charachteristicEnum!.mapping[_constLogic]
        } else {
          return _constLogic!.value.toString();
        }
      } else {
        assert(
            logics.length > 1,
            'If there is a consant, but the const name is not allowed, '
            'there needs to be another option');
      }
    }

    //TODO: for enums, all the value names must be unique in the scope as well!

    // check for reserved
    if (_reservedLogic != null) {
      return uniquifier.getUniqueName(
          initialName: _reservedLogic!.name, reserved: true);
    }

    // check for renameable
    if (_renameableLogic != null) {
      return uniquifier.getUniqueName(initialName: _renameableLogic!.name);
    }

    // pick a preferred, available, mergeable name, if one exists
    final unpreferredMergeableLogics = <Logic>[];
    final uniquifiableMergeableLogics = <Logic>[];
    for (final mergeableLogic in _mergeableLogics) {
      if (Naming.isUnpreferred(mergeableLogic.name)) {
        unpreferredMergeableLogics.add(mergeableLogic);
      } else if (!uniquifier.isAvailable(mergeableLogic.name)) {
        uniquifiableMergeableLogics.add(mergeableLogic);
      } else {
        return uniquifier.getUniqueName(initialName: mergeableLogic.name);
      }
    }

    // uniquify a preferred, mergeable name, if one exists
    if (uniquifiableMergeableLogics.isNotEmpty) {
      return uniquifier.getUniqueName(
          initialName: uniquifiableMergeableLogics.first.name);
    }

    // pick an available unpreferred mergeable name, if one exists, otherwise
    // uniquify an unpreferred mergeable name
    if (unpreferredMergeableLogics.isNotEmpty) {
      return uniquifier.getUniqueName(
          initialName: unpreferredMergeableLogics
                  .firstWhereOrNull(
                      (element) => uniquifier.isAvailable(element.name))
                  ?.name ??
              unpreferredMergeableLogics.first.name);
    }

    // pick anything (unnamed) and uniquify as necessary (considering preferred)
    // no need to prefer an available one here, since it's all unnamed
    return uniquifier.getUniqueName(
        initialName: _unnamedLogics
                .firstWhereOrNull(
                    (element) => !Naming.isUnpreferred(element.name))
                ?.name ??
            _unnamedLogics.first.name);
  }

  /// Creates an instance to represent [initialLogic] and any that merge
  /// into it.
  SynthLogic(Logic initialLogic,
      {Naming? namingOverride, bool constNameDisallowed = false})
      : isArray = initialLogic is LogicArray,
        _constNameDisallowed = constNameDisallowed {
    _addLogic(initialLogic, namingOverride: namingOverride);
  }

  /// Returns the [SynthLogic] that should be *removed*.
  static SynthLogic? tryMerge(SynthLogic a, SynthLogic b) {
    if (_constantsMergeable(a, b)) {
      // case to avoid things like a constant assigned to another constant
      a.adopt(b);
      return b;
    }

    if (!a.mergeable && !b.mergeable) {
      return null;
    }

    if (a.isNet != b.isNet) {
      // do not merge nets with non-nets
      return null;
    }

    if (a.isEnum || b.isEnum) {
      // do not merge enums with non-enums (except for constants)
      final oneIsConst = a.isConstant || b.isConstant;

      if (oneIsConst) {
        // check to make sure the constant is legal for the enum, otherwise it
        // will generate illegal verilog
        //TODO: test this scenario!

        final theConst = a.isConstant ? a : b;
        final theEnum = a.isEnum ? a : b;
        assert(theConst != theEnum,
            'Const and enum should be different SynthLogics.');

        final constVal = theConst._constLogic!.value;
        final enumMapping = theEnum.characteristicEnum!.mapping;
        if (!enumMapping.values.contains(constVal)) {
          //TODO: better exceptions
          throw Exception('Assignment of $constVal to enum'
              ' with mapping $enumMapping is not legal.');
        }
      } else {
        // if not a const scenario, check enum rules
        if (a.isEnum != b.isEnum) {
          return null;
        }

        final aEnum = a.logics.first as LogicEnum;
        final bEnum = b.logics.first as LogicEnum;
        // if the enums are incompatible, do not merge
        if (!aEnum.isEquivalentTypeTo(bEnum)) {
          return null;
        }
      }

      // otherwise, continue on with normal merging flow
    }

    if (b.mergeable) {
      a.adopt(b);
      return b;
    } else {
      b.adopt(a);
      return a;
    }
  }

  /// Indicates whether two constants can be merged.
  static bool _constantsMergeable(SynthLogic a, SynthLogic b) =>
      a.isConstant &&
      b.isConstant &&
      a._constLogic!.value == b._constLogic!.value &&
      !a._constNameDisallowed &&
      !b._constNameDisallowed;

  /// Merges [other] to be represented by `this` instead, and updates the
  /// [other] that it has been replaced.
  void adopt(SynthLogic other) {
    assert(other.mergeable || _constantsMergeable(this, other),
        'Cannot merge a non-mergeable into this.');
    assert(other.isArray == isArray, 'Cannot merge arrays and non-arrays');
    assert(
        _name == null, 'Cannot merge into this after a name has been picked.');
    assert(other._name == null,
        'Cannot merge into other after a name has been picked.');

    _constNameDisallowed |= other._constNameDisallowed;

    // only take one of the other's items if we don't have it already
    _constLogic ??= other._constLogic;
    _reservedLogic ??= other._reservedLogic;
    _renameableLogic ??= other._renameableLogic;
    _firstEnum ??= other._firstEnum;

    // the rest, take them all
    _mergeableLogics.addAll(other._mergeableLogics);
    _unnamedLogics.addAll(other._unnamedLogics);

    // keep track that it was replaced by this
    other.replacement = this;
  }

  /// Adds a new [logic] to be represented by this.
  void _addLogic(Logic logic, {Naming? namingOverride}) {
    final naming = namingOverride ?? logic.naming;
    if (logic is Const) {
      _constLogic = logic;
    } else {
      switch (naming) {
        case Naming.reserved:
          _reservedLogic = logic;
        case Naming.renameable:
          _renameableLogic = logic;
        case Naming.mergeable:
          _mergeableLogics.add(logic);
        case Naming.unnamed:
          _unnamedLogics.add(logic);
      }
    }

    if (logic is LogicEnum) {
      assert(characteristicEnum?.isEquivalentTypeTo(logic) ?? true,
          'Cannot add a LogicEnum that is not equivalent to the existing one.');

      _firstEnum ??= logic;
    }
  }

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'}, '
      'logics contained: ${logics.map((e) => e.name).toList()}';

  /// Provides a definition for a range in SV from a width.
  static String _widthToRangeDef(int width, {bool forceRange = false}) {
    if (width > 1 || forceRange) {
      return '[${width - 1}:0]';
    } else {
      return '';
    }
  }

  /// Computes the name of the signal at declaration time with appropriate
  /// dimensions included.
  String definitionName() {
    String packedDims;
    String unpackedDims;

    // we only use this for dimensions, so first is fine
    final logic = logics.first;

    if (isArray) {
      final logicArr = logic as LogicArray;

      final packedDimsBuf = StringBuffer();
      final unpackedDimsBuf = StringBuffer();

      final dims = logicArr.dimensions;
      for (var i = 0; i < dims.length; i++) {
        final dim = dims[i];
        final dimStr = _widthToRangeDef(dim, forceRange: true);
        if (i < logicArr.numUnpackedDimensions) {
          unpackedDimsBuf.write(dimStr);
        } else {
          packedDimsBuf.write(dimStr);
        }
      }

      packedDimsBuf.write(_widthToRangeDef(logicArr.elementWidth));

      packedDims = packedDimsBuf.toString();
      unpackedDims = unpackedDimsBuf.toString();
    } else {
      packedDims = _widthToRangeDef(logic.width);
      unpackedDims = '';
    }

    return [packedDims, name, unpackedDims]
        .where((e) => e.isNotEmpty)
        .join(' ');
  }
}

/// Represents an element of a [LogicArray].
///
/// Does not fully override or properly implement all characteristics of
/// [SynthLogic], so this should be used cautiously.
class SynthLogicArrayElement extends SynthLogic {
  /// The [SynthLogic] tracking the name of the direct parent array.
  final SynthLogic parentArray;

  @override
  bool get needsDeclaration => false;

  @override
  String get name {
    final parentArrayname = parentArray.replacement?.name ?? parentArray.name;
    final n = '$parentArrayname[${logic.arrayIndex!}]';
    assert(
      Sanitizer.isSanitary(
          n.substring(0, n.contains('[') ? n.indexOf('[') : null)),
      'Array name should be sanitary, but found $n',
    );
    return n;
  }

  /// The element of the [parentArray].
  final Logic logic;

  /// Creates an instance of an element of a [LogicArray].
  SynthLogicArrayElement(this.logic, this.parentArray)
      : assert(logic.isArrayMember,
            'Should only be used for elements in a LogicArray'),
        super(logic);

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'},'
      ' parentArray=($parentArray), element ${logic.arrayIndex}, logic: $logic'
      ' logics contained: ${logics.map((e) => e.name).toList()}';
}

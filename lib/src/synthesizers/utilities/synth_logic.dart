// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_logic.dart
// Definitions for signal representations during generation
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents a logic signal in the generated code within a module.
@internal
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

  /// The parent [SynthModuleDefinition] that this [SynthLogic] belongs to.
  final SynthModuleDefinition parentSynthModuleDefinition;

  /// Indicates if this signal is an element of a [LogicStructure] that is a
  /// port.
  ///
  /// Note that this is distinct from a port that is an element of a
  /// [LogicStructure] that is not a port.
  ///
  /// If a [module] is provided, then it only returns true if the parent
  /// structure is a port of that [module].
  bool isStructPortElement([Module? module]) =>
      (this is! SynthLogicArrayElement) &&
      logics.any((e) =>
          e.isPort &&
          e.parentStructure != null &&
          e.parentStructure!.isPort &&
          (module == null || e.parentStructure!.parentModule == module));

  /// Indicates if this signal is a port, optionally for a specific [module].
  bool isPort([Module? module]) =>
      // we can rely on ports being the reserved logic (optimization)
      _reservedLogic != null &&
      _reservedLogic!.isPort &&
      (module == null || _reservedLogic!.parentModule == module);

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

  /// If set, then this should never pick the constant as the name.
  bool get constNameDisallowed => _constNameDisallowed;
  bool _constNameDisallowed;

  /// Whether this signal should be declared.
  bool get needsDeclaration =>
      !(isConstant && !_constNameDisallowed) && !declarationCleared;

  /// Whether this signal's declaration has been cleared (via
  /// [clearDeclaration]).
  bool get declarationCleared => _declarationCleared;
  bool _declarationCleared = false;

  /// Clears the declaration requirement for this [SynthLogic].
  ///
  /// Note that this can also apply to array elements.
  void clearDeclaration() {
    _declarationCleared = true;
  }

  /// Indicates if this signal definition can be cleared via [clearDeclaration].
  ///
  /// If it is `false`, then this signal cannot be cleared.  If `true`, there
  /// may be additional conditions that prevent clearing.
  bool get isClearable => mergeable;

  /// The source connections to any [Logic] in this [SynthLogic] which are not
  /// also contained within this [SynthLogic].
  Iterable<Logic> get srcConnections {
    final containedLogics = logics.toSet();
    return logics
        .map((e) => e.srcConnections)
        .flattened
        .where((e) => !containedLogics.contains(e));
  }

  /// The destination connections to any [Logic] in this [SynthLogic] which are
  /// not also contained within this [SynthLogic].
  Iterable<Logic> get dstConnections {
    final containedLogics = logics.toSet();
    return logics
        .map((e) => e.dstConnections)
        .flattened
        .where((e) => !containedLogics.contains(e));
  }

  /// Indicates if there are any [dstConnections] present in
  /// [parentSynthModuleDefinition].
  bool hasDstConnectionsPresent() =>
      logics.any((logic) =>
          logic is Const || // in case of net, could be const dest
          (logic.isInput || logic.isInOut) &&
              parentSynthModuleDefinition
                  .isSubmoduleAndPresent(logic.parentModule)) ||
      dstConnections
          .any(parentSynthModuleDefinition.logicHasPresentSynthLogic) ||
      (isNet &&
          srcConnections
              .any(parentSynthModuleDefinition.logicHasPresentSynthLogic));

  /// Indicates if there are any [srcConnections] present in
  /// [parentSynthModuleDefinition].
  bool hasSrcConnectionsPresent() =>
      logics.any((logic) =>
          logic is Const ||
          (logic.isOutput || logic.isInOut) &&
              parentSynthModuleDefinition
                  .isSubmoduleAndPresent(logic.parentModule)) ||
      srcConnections
          .any(parentSynthModuleDefinition.logicHasPresentSynthLogic) ||
      (isNet &&
          dstConnections
              .any(parentSynthModuleDefinition.logicHasPresentSynthLogic));

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
    assert(_name != null, 'Name has not been picked for $this.');
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
  }

  /// Finds the best name from the collection of [Logic]s.
  String _findName(Uniquifier uniquifier) {
    // check for const
    if (_constLogic != null) {
      if (!_constNameDisallowed) {
        return _constLogic!.value.toString();
      } else {
        assert(
            logics.length > 1,
            'If there is a constant, but the const name is not allowed, '
            'there needs to be another option');
      }
    }

    // check for reserved
    if (_reservedLogic != null) {
      return uniquifier.getUniqueName(
          initialName: _reservedLogic!.name, reserved: true);
    }

    // check for renameable
    if (_renameableLogic != null) {
      return uniquifier.getUniqueName(
          initialName: _renameableLogic!.preferredSynthName);
    }

    // pick a preferred, available, mergeable name, if one exists
    final unpreferredMergeableLogics = <Logic>[];
    final uniquifiableMergeableLogics = <Logic>[];
    for (final mergeableLogic in _mergeableLogics) {
      if (Naming.isUnpreferred(mergeableLogic.name)) {
        unpreferredMergeableLogics.add(mergeableLogic);
      } else if (!uniquifier.isAvailable(mergeableLogic.preferredSynthName)) {
        uniquifiableMergeableLogics.add(mergeableLogic);
      } else {
        return uniquifier.getUniqueName(
            initialName: mergeableLogic.preferredSynthName);
      }
    }

    // uniquify a preferred, mergeable name, if one exists
    if (uniquifiableMergeableLogics.isNotEmpty) {
      return uniquifier.getUniqueName(
          initialName: uniquifiableMergeableLogics.first.preferredSynthName);
    }

    // pick an available unpreferred mergeable name, if one exists, otherwise
    // uniquify an unpreferred mergeable name
    if (unpreferredMergeableLogics.isNotEmpty) {
      return uniquifier.getUniqueName(
          initialName: unpreferredMergeableLogics
                  .firstWhereOrNull((element) =>
                      uniquifier.isAvailable(element.preferredSynthName))
                  ?.preferredSynthName ??
              unpreferredMergeableLogics.first.preferredSynthName);
    }

    // pick anything (unnamed) and uniquify as necessary (considering preferred)
    // no need to prefer an available one here, since it's all unnamed
    return uniquifier.getUniqueName(
        initialName: _unnamedLogics
                .firstWhereOrNull((element) =>
                    !Naming.isUnpreferred(element.preferredSynthName))
                ?.preferredSynthName ??
            _unnamedLogics.first.preferredSynthName);
  }

  /// Creates an instance to represent [initialLogic] and any that merge
  /// into it.
  SynthLogic(Logic initialLogic,
      {required this.parentSynthModuleDefinition,
      Naming? namingOverride,
      bool constNameDisallowed = false})
      : isArray = initialLogic is LogicArray,
        _constNameDisallowed = constNameDisallowed {
    _addLogic(initialLogic, namingOverride: namingOverride);
  }

  /// Returns `null` if the merge did not occur, and a pair of the `removed` and
  /// `kept` [SynthLogic]s otherwise.
  static ({SynthLogic removed, SynthLogic kept})? tryMerge(
      SynthLogic a, SynthLogic b) {
    if (_constantsMergeable(a, b)) {
      // case to avoid things like a constant assigned to another constant
      a.adopt(b);
      return (removed: b, kept: a);
    }

    if (!a.mergeable && !b.mergeable) {
      return null;
    }

    if (a.isNet != b.isNet) {
      // do not merge nets with non-nets
      return null;
    }

    if (b.mergeable) {
      a.adopt(b);
      return (removed: b, kept: a);
    } else {
      b.adopt(a);
      return (removed: a, kept: b);
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
  ///
  /// If [force] is `true`, then it will adopt even if both are non-mergeable.
  void adopt(SynthLogic other, {bool force = false}) {
    assert(force || other.mergeable || _constantsMergeable(this, other),
        'Cannot merge a non-mergeable into this.');
    assert(other.isArray == isArray, 'Cannot merge arrays and non-arrays');
    assert(other.width == width,
        'Cannot merge logics of different widths: $width vs ${other.width}');
    assert(
        other != this, 'Suspicious attempt to merge a SynthLogic into itself.');

    _constNameDisallowed |= other._constNameDisallowed;

    // only take one of the other's items if we don't have it already
    _constLogic ??= other._constLogic;
    _reservedLogic ??= other._reservedLogic;
    _renameableLogic ??= other._renameableLogic;

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
  }

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'}, '
      'logics contained: ${logics.map((e) => e.preferredSynthName).toList()}';

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
  /// The [SynthLogic] tracking the direct parent array.
  SynthLogic get parentArray =>
      parentSynthModuleDefinition.getSynthLogic(logic.parentStructure)!;

  @override
  bool get needsDeclaration => false;

  @override
  bool get mergeable =>
      // we can't merge elements of arrays safely, we could lose an assignment
      false;

  @override
  bool isPort([Module? module]) =>
      super.isPort(module) ||
      // we cannot just use `super.isPort` since we can't rely on only using
      // `_reservedLogic`
      logics.any(
          (l) => l.isPort && (module == null || l.parentModule == module)) ||
      parentArray.isPort(module);

  @override
  bool get isClearable =>
      !isPort(parentSynthModuleDefinition.module) && parentArray.isClearable;

  @override
  bool hasSrcConnectionsPresent() =>
      super.hasSrcConnectionsPresent() ||
      (parentArray is! SynthLogicArrayElement && // in case merge with non array
          parentArray.hasSrcConnectionsPresent());

  @override
  bool hasDstConnectionsPresent() =>
      super.hasDstConnectionsPresent() ||
      (parentArray is! SynthLogicArrayElement && // in case merge with non array
          parentArray.hasDstConnectionsPresent());

  @override
  void adopt(SynthLogic other, {bool force = false}) {
    super.adopt(other, force: force);

    // in case we're merging array elements with a force or something, and maybe
    // there was a renameable in there instead of mergeable or something, then
    // we need to make sure it still gets in there.
    if (force) {
      for (final otherLogic in other.logics) {
        if (!logics.contains(otherLogic)) {
          _mergeableLogics.add(otherLogic);
        }
      }
    }
  }

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
  SynthLogicArrayElement(this.logic,
      {required super.parentSynthModuleDefinition})
      : assert(logic.isArrayMember,
            'Should only be used for elements in a LogicArray'),
        super(logic) {
    // make sure we have created the synthLogic for the parent array
    parentArray;
  }

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'},'
      ' parentArray=($parentArray), element ${logic.arrayIndex}, logic: $logic'
      ' logics contained: ${logics.map((e) => e.name).toList()}';
}

extension on Logic {
  /// Returns the preferred name for this [Logic] while generating in the synth
  /// stack.
  String get preferredSynthName => naming == Naming.reserved
      // if reserved, keep the exact name
      ? name
      : isArrayMember
          // arrays nicely name their elements already
          ? name
          // sanitize to remove any `.` in struct names
          // the base `name` will be returned if not a structure.
          : Sanitizer.sanitizeSV(structureName);
}

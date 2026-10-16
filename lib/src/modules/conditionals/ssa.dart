// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// ssa.dart
// Definitions for usage with combinational SSA.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A signal that represents an SSA node in [Combinational.ssa] which is
/// associated with one specific [Combinational].
class SsaLogic extends Logic {
  /// The signal that this represents.
  final Logic ref;

  /// A unique identifier for the context of which [Combinational.ssa] it is
  /// associated with.
  final int context;

  /// Constructs a new SSA node referring to a signal in a specific context.
  SsaLogic(this.ref, this.context)
      : super(width: ref.width, name: ref.name, naming: Naming.mergeable);

  @override
  SsaLogic clone({String? name}) =>
      throw UnimplementedError('Should not clone an SsaLogic');

  /// Creates an SSA proxy for [ref], preserving its concrete type when that
  /// type can be reconstructed as a driveable signal.
  static Logic create(
    Logic ref,
    int context, {
    required bool preserveTypes,
  }) {
    if (preserveTypes && _canPreserveType(ref)) {
      final proxy = ref.clone(name: ref.name);
      if (proxy.runtimeType != ref.runtimeType) {
        throw LogicConstructionException(
          'SSA proxy clone did not preserve ${ref.runtimeType}.',
        );
      }
      _markProxy(ref, proxy, context);
      return proxy;
    }

    return SsaLogic(ref, context);
  }

  /// Returns whether [signal] is an SSA proxy in [context].
  static bool isSsaProxy(Logic signal, {required int context}) {
    if (signal is SsaLogic) {
      return signal.context == context;
    }
    return _typedReferences[signal]?.context == context;
  }

  /// Returns the signal represented by an SSA [signal] in [context].
  static Logic referenceOf(Logic signal, {required int context}) {
    if (signal is SsaLogic && signal.context == context) {
      return signal.ref;
    }

    final reference = _typedReferences[signal];
    if (reference != null && reference.context == context) {
      return reference.ref;
    }

    throw ArgumentError.value(
      signal,
      'signal',
      'Not an SSA proxy in context $context.',
    );
  }

  /// Returns all leaf-level SSA proxies contained by [signal].
  static Iterable<Logic> proxyLeaves(Logic signal, {required int context}) {
    if (signal is LogicStructure) {
      return signal.leafElements.where(
        (element) => isSsaProxy(element, context: context),
      );
    }

    return isSsaProxy(signal, context: context) ? [signal] : const [];
  }

  /// Returns whether [signal] contains a type-preserving SSA proxy.
  static bool containsTypedProxy(Logic signal) => signal is LogicStructure
      ? signal.leafElements.any(
          (element) => _typedReferences[element] != null,
        )
      : _typedReferences[signal] != null;

  /// Creates a driveable signal with [reference]'s concrete type.
  static Logic cloneLike(
    Logic reference,
    Logic currentValue, {
    required String name,
  }) =>
      _typedReferences[currentValue] != null
          ? reference.clone(name: name)
          : Logic(name: name, width: reference.width, naming: Naming.mergeable);

  /// Returns the zero-value driver used to initialize an SSA branch.
  ///
  /// A [LogicEnum] must receive a variable driver so its mapping can apply the
  /// same invalid-value handling as a width-only SSA node.
  static dynamic branchDefaultValue(Logic signal) => signal is LogicEnum
      ? (Logic(
          name: '${signal.name}_ssa_default',
          width: signal.width,
          naming: Naming.mergeable,
        )..gets(Const(0, width: signal.width)))
      : 0;

  static bool _canPreserveType(Logic ref) {
    if (ref is Const || ref is LogicNet || ref is SsaLogic) {
      return false;
    }
    if (ref is! LogicStructure) {
      return ref.runtimeType != Logic;
    }

    return ref.leafElements.every(
      (element) => element is! Const && element is! LogicNet,
    );
  }

  static void _markProxy(Logic ref, Logic proxy, int context) {
    if (ref is LogicStructure || proxy is LogicStructure) {
      if (ref is! LogicStructure ||
          proxy is! LogicStructure ||
          ref.elements.length != proxy.elements.length) {
        throw LogicConstructionException(
          'SSA proxy clone did not preserve the structure of ${ref.name}.',
        );
      }

      for (var index = 0; index < ref.elements.length; index++) {
        _markProxy(ref.elements[index], proxy.elements[index], context);
      }
      return;
    }

    _typedReferences[proxy] = _SsaReference(ref, context);
  }
}

class _SsaReference {
  final Logic ref;
  final int context;

  const _SsaReference(this.ref, this.context);
}

final Expando<_SsaReference> _typedReferences =
    Expando<_SsaReference>('typedSsaReferences');

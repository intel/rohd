// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// namer.dart
// Central collision-free naming for signals and instances within a module.
//
// 2026 April 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Central namer that manages collision-free names for both signals and
/// submodule instances within a single module scope.
///
/// All identifiers (signals and instances) share a single namespace,
/// ensuring no name collisions in the generated SystemVerilog.
///
/// Port names are reserved at construction time.  Internal signal names
/// are assigned lazily on the first [signalNameOfBest] call.  Instance names
/// are assigned lazily on the first [instanceNameOf] call.
@internal
class Namer {
  /// Canonical base name for synthesis-created array slice operations.
  static const String synthArraySliceOperationName = 'array_slice';

  /// Canonical base name for synthesis-created array concat operations.
  static const String synthArrayConcatOperationName = 'array_concat';

  /// Canonical base name for synthesis-created structure slice operations.
  static const String synthStructureSliceOperationName = 'struct_slice';

  /// Canonical base name for synthesis-created structure concat operations.
  static const String synthStructureConcatOperationName = 'struct_concat';

  /// Returns the canonical base instance name for a synthesis-created
  /// structural operation that targets [destination].
  ///
  /// The numeric suffix is derived from [destination]'s structural position,
  /// not from the order in which a backend asks for names. This keeps helper
  /// operation names stable across output formats that traverse a module in
  /// different orders.
  static String synthOperationInstanceName({
    required String operationName,
    required Logic destination,
  }) =>
      '${Sanitizer.sanitizeSV(operationName)}_'
      '${_synthOperationDestinationSuffix(destination)}';

  /// The [Uniquifier] that manages the shared namespace for this module.
  final Uniquifier _uniquifier;

  /// Cache of resolved names for internal (non-port) signals only.
  /// Port names are returned directly from [_portLogics] and never cached here.
  final Map<Logic, String> _signalNames = {};

  /// Cache of resolved instance names, keyed by [Module.instanceNameKey].
  ///
  /// Instance-name lookup claims names in [_uniquifier]. Without this cache,
  /// repeated synthesis passes over the same module hierarchy would allocate
  /// fresh suffixes for the same submodule instances.
  final Map<Object, String> _instanceNames = {};

  /// The set of port [Logic] objects, for O(1) port membership tests.
  final Set<Logic> _portLogics;

  // ─── Construction ───────────────────────────────────────────────

  Namer._({required Uniquifier uniquifier, required Set<Logic> portLogics})
      : _uniquifier = uniquifier,
        _portLogics = portLogics;

  /// Creates a [Namer] for the given [module]'s ports.
  ///
  /// Port names are reserved in the shared namespace.  Port names are
  /// guaranteed sanitary by [Module]'s `_checkForSafePortName`.
  factory Namer.forModule(Module module) {
    final portLogics = <Logic>{
      ...module.inputs.values,
      ...module.outputs.values,
      ...module.inOuts.values,
    };

    final uniquifier = Uniquifier();
    for (final logic in portLogics) {
      uniquifier.getUniqueName(initialName: logic.name, reserved: true);
    }

    return Namer._(uniquifier: uniquifier, portLogics: portLogics);
  }

  // ─── Name availability / allocation ─────────────────────────────

  /// Returns `true` if [name] has not yet been claimed in the namespace.
  @visibleForTesting
  bool isAvailable(String name) => _uniquifier.isAvailable(name);

  static String _synthOperationDestinationSuffix(Logic destination) {
    final parts = <int>[
      ..._modulePathIndices(destination.parentModule),
      ..._logicLocationIndices(destination),
    ];

    return parts.isEmpty ? '0' : parts.join('_');
  }

  static List<int> _modulePathIndices(Module? module) {
    if (module == null) {
      return const [0];
    }

    final parent = module.parent;
    if (parent == null) {
      return const [0];
    }

    final siblings = parent.subModules.toList();
    final index =
        siblings.indexWhere((submodule) => identical(submodule, module));
    return [
      ..._modulePathIndices(parent),
      if (index < 0) 0 else index,
    ];
  }

  static List<int> _logicLocationIndices(Logic destination) {
    final elementPath = <int>[];
    var root = destination;
    while (root.parentStructure != null) {
      final parent = root.parentStructure!;
      final index =
          parent.elements.indexWhere((element) => identical(element, root));
      elementPath.insert(0, index < 0 ? root.arrayIndex ?? 0 : index);
      root = parent;
    }

    final module = root.parentModule;
    if (module == null) {
      return [0, ...elementPath];
    }

    final location = _logicLocationInModule(module, root);
    return [...location, ...elementPath];
  }

  static List<int> _logicLocationInModule(Module module, Logic root) {
    final inputIndex = _identityIndex(module.inputs.values, root);
    if (inputIndex >= 0) {
      return [0, inputIndex];
    }

    final outputIndex = _identityIndex(module.outputs.values, root);
    if (outputIndex >= 0) {
      return [1, outputIndex];
    }

    final inOutIndex = _identityIndex(module.inOuts.values, root);
    if (inOutIndex >= 0) {
      return [2, inOutIndex];
    }

    final internalIndex = _identityIndex(module.internalSignals, root);
    if (internalIndex >= 0) {
      return [3, internalIndex];
    }

    return const [4, 0];
  }

  static int _identityIndex(Iterable<Logic> logics, Logic target) {
    var index = 0;
    for (final logic in logics) {
      if (identical(logic, target)) {
        return index;
      }
      index++;
    }
    return -1;
  }

  // ─── Instance naming (Module → String) ──────────────────────────

  /// Returns the canonical instance name for [submodule].
  ///
  /// The first call allocates a collision-free name in the shared namespace;
  /// later calls for the same [Module.instanceNameKey] return the cached name.
  String instanceNameOf(Module submodule) {
    final key = submodule.instanceNameKey;
    final cached = _instanceNames[key];
    if (cached != null) {
      return cached;
    }

    final name = _uniquifier.getUniqueName(
      initialName: Sanitizer.sanitizeSV(submodule.uniqueInstanceName),
      reserved: submodule.reserveName,
    );
    _instanceNames[key] = name;
    return name;
  }

  // ─── Signal naming (Logic → String) ─────────────────────────────

  /// Returns the canonical name for [logic].
  ///
  /// The first call for a given [logic] allocates a collision-free name
  /// via the underlying [Uniquifier].  Subsequent calls return the cached
  /// result in O(1).
  String _signalNameOf(Logic logic) {
    final cached = _signalNames[logic];
    if (cached != null) {
      return cached;
    }

    if (_portLogics.contains(logic)) {
      return logic.name;
    }

    String base;
    final isReservedInternal = logic.naming == Naming.reserved && !logic.isPort;
    if (logic.naming == Naming.reserved || logic.isArrayMember) {
      base = logic.name;
    } else {
      base = Sanitizer.sanitizeSV(logic.structureName);
    }

    final name = _uniquifier.getUniqueName(
      initialName: base,
      reserved: isReservedInternal,
    );
    _signalNames[logic] = name;
    return name;
  }

  /// Returns the synthesis-level signal name for [logic].
  ///
  /// Equivalent to the internal [_signalNameOf] allocation but exposed for
  /// use in wave-dumping and tests.
  @visibleForTesting
  String signalNameOf(Logic logic) => _signalNameOf(logic);

  /// The base name that would be used for [logic] before uniquification.
  static String baseName(Logic logic) =>
      (logic.naming == Naming.reserved || logic.isArrayMember)
          ? logic.name
          : Sanitizer.sanitizeSV(logic.structureName);

  /// Chooses the best name from a pool of merged [Logic] signals.
  ///
  /// When [constValue] is provided and [constNameDisallowed] is `false`,
  /// the constant's value string is used directly as the name (no
  /// uniquification).  When [constNameDisallowed] is `true`, the constant
  /// is excluded from the candidate pool and the normal priority applies.
  ///
  /// Priority (after constant handling):
  ///   1. Port of this module (always wins — its name is already reserved).
  ///   2. Reserved internal signal (exact name, throws on collision).
  ///   3. Renameable signal.
  ///   4. Preferred-available mergeable (base name not yet taken).
  ///   5. Preferred-uniquifiable mergeable.
  ///   6. Available-unpreferred mergeable.
  ///   7. First unpreferred mergeable.
  ///   8. Unnamed (prefer non-unpreferred base name).
  ///
  /// The winning name is allocated once and cached for the chosen [Logic].
  /// All other non-port [Logic]s in [candidates] are also cached to the
  /// same name.
  String signalNameOfBest(
    Iterable<Logic> candidates, {
    Const? constValue,
    bool constNameDisallowed = false,
  }) {
    if (constValue != null && !constNameDisallowed) {
      return constValue.value.toString();
    }

    Logic? port;
    Logic? reserved;
    Logic? renameable;
    final preferredMergeable = <Logic>[];
    final unpreferredMergeable = <Logic>[];
    final unnamed = <Logic>[];

    for (final logic in candidates) {
      if (_portLogics.contains(logic)) {
        port = logic;
      } else if (logic.isPort) {
        if (Naming.isUnpreferred(baseName(logic))) {
          unpreferredMergeable.add(logic);
        } else {
          preferredMergeable.add(logic);
        }
      } else if (logic.naming == Naming.reserved) {
        reserved = logic;
      } else if (logic.naming == Naming.renameable) {
        renameable = logic;
      } else if (logic.naming == Naming.mergeable) {
        if (Naming.isUnpreferred(baseName(logic))) {
          unpreferredMergeable.add(logic);
        } else {
          preferredMergeable.add(logic);
        }
      } else {
        unnamed.add(logic);
      }
    }

    if (port != null) {
      return _nameAndCacheAll(port, candidates);
    }

    if (reserved != null) {
      return _nameAndCacheAll(reserved, candidates);
    }

    if (renameable != null) {
      return _nameAndCacheAll(renameable, candidates);
    }

    if (preferredMergeable.isNotEmpty) {
      final best = preferredMergeable.firstWhereOrNull(
            (e) => isAvailable(baseName(e)),
          ) ??
          preferredMergeable.first;
      return _nameAndCacheAll(best, candidates);
    }

    if (unpreferredMergeable.isNotEmpty) {
      final best = unpreferredMergeable.firstWhereOrNull(
            (e) => isAvailable(baseName(e)),
          ) ??
          unpreferredMergeable.first;
      return _nameAndCacheAll(best, candidates);
    }

    if (unnamed.isNotEmpty) {
      final best =
          unnamed.firstWhereOrNull((e) => !Naming.isUnpreferred(baseName(e))) ??
              unnamed.first;
      return _nameAndCacheAll(best, candidates);
    }

    throw StateError('No Logic candidates to name.');
  }

  /// Names [chosen] with the single-signal allocator, then caches the
  /// same name for all other non-port [Logic]s in [all].
  String _nameAndCacheAll(Logic chosen, Iterable<Logic> all) {
    final name = _signalNameOf(chosen);
    for (final logic in all) {
      if (!identical(logic, chosen) && !_portLogics.contains(logic)) {
        _signalNames[logic] = name;
      }
    }
    return name;
  }
}

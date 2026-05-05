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
/// are assigned lazily on the first [signalNameOf] call.  Instance names
/// are allocated explicitly via [allocateRawName].
@internal
class Namer {
  // ─── Shared namespace ───────────────────────────────────────────

  final Uniquifier _uniquifier;

  /// Cache of resolved names for internal (non-port) signals only.
  /// Port names are returned directly from [_portLogics] and never cached here.
  final Map<Logic, String> _signalNames = {};

  /// The set of port [Logic] objects, for O(1) port membership tests.
  final Set<Logic> _portLogics;

  // ─── Construction ───────────────────────────────────────────────

  Namer._({
    required Uniquifier uniquifier,
    required Set<Logic> portLogics,
  })  : _uniquifier = uniquifier,
        _portLogics = portLogics;

  /// Creates a [Namer] for the given module ports.
  ///
  /// Port names are reserved in the shared namespace.  Port names are
  /// guaranteed sanitary by [Module]'s `_checkForSafePortName`.
  factory Namer.forModule({
    required Map<String, Logic> inputs,
    required Map<String, Logic> outputs,
    required Map<String, Logic> inOuts,
  }) {
    final portLogics = <Logic>{
      ...inputs.values,
      ...outputs.values,
      ...inOuts.values,
    };

    final uniquifier = Uniquifier();
    for (final logic in portLogics) {
      uniquifier.getUniqueName(initialName: logic.name, reserved: true);
    }

    return Namer._(
      uniquifier: uniquifier,
      portLogics: portLogics,
    );
  }

  // ─── Name availability / allocation ─────────────────────────────

  /// Returns `true` if [name] has not yet been claimed in the namespace.
  bool isAvailable(String name) => _uniquifier.isAvailable(name);

  /// Allocates a collision-free name in the shared namespace.
  ///
  /// When [reserved] is `true`, the exact [baseName] (after sanitization)
  /// is claimed without modification; an exception is thrown if it collides.
  String allocateRawName(String baseName, {bool reserved = false}) =>
      _uniquifier.getUniqueName(
        initialName: Sanitizer.sanitizeSV(baseName),
        reserved: reserved,
      );

  // ─── Signal naming (Logic → String) ─────────────────────────────

  /// Returns the canonical name for [logic].
  ///
  /// The first call for a given [logic] allocates a collision-free name
  /// via the underlying [Uniquifier].  Subsequent calls return the cached
  /// result in O(1).
  String signalNameOf(Logic logic) {
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
      final best = preferredMergeable
              .firstWhereOrNull((e) => isAvailable(baseName(e))) ??
          preferredMergeable.first;
      return _nameAndCacheAll(best, candidates);
    }

    if (unpreferredMergeable.isNotEmpty) {
      final best = unpreferredMergeable
              .firstWhereOrNull((e) => isAvailable(baseName(e))) ??
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

  /// Names [chosen] via [signalNameOf], then caches the same name for all
  /// other non-port [Logic]s in [all].
  String _nameAndCacheAll(Logic chosen, Iterable<Logic> all) {
    final name = signalNameOf(chosen);
    for (final logic in all) {
      if (!identical(logic, chosen) && !_portLogics.contains(logic)) {
        _signalNames[logic] = name;
      }
    }
    return name;
  }
}

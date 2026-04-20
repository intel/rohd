// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_namer.dart
// Collision-free signal naming within a module scope.
//
// 2026 April 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Assigns collision-free names to [Logic] signals within a single module.
///
/// Wraps a [Uniquifier] with a sparse Logic→String cache so that each
/// signal is named exactly once and every subsequent lookup is O(1).
///
/// Port names are reserved at construction time.  Internal signals are
/// named lazily on the first [nameOf] call.
@internal
class SignalNamer {
  /// Controls whether synthesized signal names and instance names must be
  /// unique across both namespaces.
  ///
  /// When `true` (the default), central naming cross-checks both namespaces
  /// during allocation so that no identifier appears as both a signal and an
  /// instance name.  This is necessary for simulators like Icarus Verilog
  /// that reject duplicate identifiers even across namespace boundaries.
  ///
  /// When `false`, signal and instance names are uniquified independently,
  /// matching strict SystemVerilog semantics where instance and signal
  /// identifiers occupy separate namespaces.
  static bool uniquifySignalAndInstanceNames = true;

  final Uniquifier _uniquifier;
  final bool Function(String name) _isAvailableInOtherNamespace;

  /// Sparse cache: only entries where the canonical name has been resolved.
  /// Ports whose sanitized name == logic.name may be absent (fast-path
  /// through [_portLogics] check).
  final Map<Logic, String> _names = {};

  /// The set of port [Logic] objects, for O(1) port membership tests.
  final Set<Logic> _portLogics;

  SignalNamer._({
    required Uniquifier uniquifier,
    required Map<Logic, String> portRenames,
    required Set<Logic> portLogics,
    required bool Function(String name) isAvailableInOtherNamespace,
  })  : _uniquifier = uniquifier,
        _portLogics = portLogics,
        _isAvailableInOtherNamespace = isAvailableInOtherNamespace {
    _names.addAll(portRenames);
  }

  /// Creates a [SignalNamer] for the given module ports.
  ///
  /// Sanitized port names are reserved in the namespace.  Ports whose
  /// sanitized name differs from [Logic.name] are cached immediately.
  factory SignalNamer.forModule({
    required Map<String, Logic> inputs,
    required Map<String, Logic> outputs,
    required Map<String, Logic> inOuts,
    bool Function(String name)? isAvailableInOtherNamespace,
  }) {
    final portRenames = <Logic, String>{};
    final portLogics = <Logic>{};
    final portNames = <String>[];

    void collectPort(String rawName, Logic logic) {
      final sanitized = Sanitizer.sanitizeSV(rawName);
      portNames.add(sanitized);
      portLogics.add(logic);
      if (sanitized != logic.name) {
        portRenames[logic] = sanitized;
      }
    }

    for (final entry in inputs.entries) {
      collectPort(entry.key, entry.value);
    }
    for (final entry in outputs.entries) {
      collectPort(entry.key, entry.value);
    }
    for (final entry in inOuts.entries) {
      collectPort(entry.key, entry.value);
    }

    // Claim each port name as reserved so that:
    //  (a) non-reserved signals can't steal them, and
    //  (b) a second reserved signal with the same name throws.
    final uniquifier = Uniquifier();
    for (final name in portNames) {
      uniquifier.getUniqueName(initialName: name, reserved: true);
    }

    return SignalNamer._(
      uniquifier: uniquifier,
      portRenames: portRenames,
      portLogics: portLogics,
      isAvailableInOtherNamespace: isAvailableInOtherNamespace ?? (_) => true,
    );
  }

  bool _isAvailable(String name, {bool reserved = false}) =>
      _uniquifier.isAvailable(name, reserved: reserved) &&
      (!uniquifySignalAndInstanceNames || _isAvailableInOtherNamespace(name));

  String _allocateUniqueName(String baseName, {bool reserved = false}) {
    if (reserved) {
      if (!_isAvailable(baseName, reserved: true)) {
        throw UnavailableReservedNameException(baseName);
      }

      _uniquifier.getUniqueName(initialName: baseName, reserved: true);
      return baseName;
    }

    var candidate = baseName;
    var suffix = 0;
    while (!_isAvailable(candidate)) {
      candidate = '${baseName}_$suffix';
      suffix++;
    }

    _uniquifier.getUniqueName(initialName: candidate);
    return candidate;
  }

  /// Returns the canonical name for [logic].
  ///
  /// The first call for a given [logic] allocates a collision-free name
  /// via the underlying [Uniquifier].  Subsequent calls return the cached
  /// result in O(1).
  String nameOf(Logic logic) {
    // Fast path: already named (port rename or previously-queried signal).
    final cached = _names[logic];
    if (cached != null) {
      return cached;
    }

    // Port whose sanitized name == logic.name — already reserved.
    if (_portLogics.contains(logic)) {
      return logic.name;
    }

    // First time seeing this internal signal — derive base name.
    String baseName;
    // Only treat as reserved for Uniquifier purposes if this is a true
    // reserved internal signal (not a submodule port that happens to have
    // Naming.reserved).
    final isReservedInternal = logic.naming == Naming.reserved && !logic.isPort;
    if (logic.naming == Naming.reserved || logic.isArrayMember) {
      baseName = logic.name;
    } else {
      baseName = Sanitizer.sanitizeSV(logic.structureName);
    }

    final name = _allocateUniqueName(
      baseName,
      reserved: isReservedInternal,
    );
    _names[logic] = name;
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
  String nameOfBest(
    Iterable<Logic> candidates, {
    Const? constValue,
    bool constNameDisallowed = false,
  }) {
    // Constant whose literal value string is the name.
    if (constValue != null && !constNameDisallowed) {
      return constValue.value.toString();
    }

    // Classify using _portLogics membership (context-aware) rather than
    // Logic.naming (context-independent), because submodule ports have
    // Naming.reserved but should NOT be treated as reserved here.
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
        // Submodule port — treat as mergeable regardless of intrinsic naming,
        // matching SynthModuleDefinition's namingOverride convention.
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

    // Port of this module — name already reserved in namespace.
    if (port != null) {
      return _nameAndCacheAll(port, candidates);
    }

    // Reserved internal — must keep exact name (throws on collision).
    if (reserved != null) {
      return _nameAndCacheAll(reserved, candidates);
    }

    // Renameable — preferred base, uniquified if needed.
    if (renameable != null) {
      return _nameAndCacheAll(renameable, candidates);
    }

    // Preferred-available mergeable.
    for (final logic in preferredMergeable) {
      if (_isAvailable(baseName(logic))) {
        return _nameAndCacheAll(logic, candidates);
      }
    }

    // Preferred-uniquifiable mergeable.
    if (preferredMergeable.isNotEmpty) {
      return _nameAndCacheAll(preferredMergeable.first, candidates);
    }

    // Unpreferred mergeable — prefer available.
    if (unpreferredMergeable.isNotEmpty) {
      final best = unpreferredMergeable
              .firstWhereOrNull((e) => _isAvailable(baseName(e))) ??
          unpreferredMergeable.first;
      return _nameAndCacheAll(best, candidates);
    }

    // Unnamed — prefer non-unpreferred base name.
    if (unnamed.isNotEmpty) {
      final best =
          unnamed.firstWhereOrNull((e) => !Naming.isUnpreferred(baseName(e))) ??
              unnamed.first;
      return _nameAndCacheAll(best, candidates);
    }

    throw StateError('No Logic candidates to name.');
  }

  /// Names [chosen] via [nameOf], then caches the same name for all other
  /// non-port [Logic]s in [all].
  String _nameAndCacheAll(Logic chosen, Iterable<Logic> all) {
    final name = nameOf(chosen);
    for (final logic in all) {
      if (!identical(logic, chosen) && !_portLogics.contains(logic)) {
        _names[logic] = name;
      }
    }
    return name;
  }

  /// Allocates a collision-free name for a non-signal artifact (wire,
  /// instance, etc.).
  ///
  /// When [reserved] is `true`, the exact [baseName] (after sanitization)
  /// is claimed without modification; an exception is thrown if it collides.
  String allocate(String baseName, {bool reserved = false}) =>
      _allocateUniqueName(
        Sanitizer.sanitizeSV(baseName),
        reserved: reserved,
      );

  /// Returns `true` if [name] has not yet been claimed in this namespace.
  bool isAvailable(String name) => _isAvailable(name);
}

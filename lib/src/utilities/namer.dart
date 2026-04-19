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
/// Signal names and instance names occupy separate namespaces (matching
/// SystemVerilog semantics), but can optionally be cross-checked via
/// [uniquifySignalAndInstanceNames] for simulator compatibility.
///
/// Port names are reserved at construction time.  Internal signal names
/// are assigned lazily on the first [signalNameOf] call.  Instance names
/// are allocated explicitly via [allocateInstanceName].
@internal
class Namer {
  /// Controls whether signal names and instance names must be unique
  /// across both namespaces.
  ///
  /// When `true` (the default), allocations cross-check both namespaces
  /// so that no identifier appears as both a signal and an instance name.
  /// This is necessary for simulators like Icarus Verilog that reject
  /// duplicate identifiers even across namespace boundaries.
  ///
  /// When `false`, signal and instance names are uniquified independently,
  /// matching strict SystemVerilog semantics where instance and signal
  /// identifiers occupy separate namespaces.
  static bool uniquifySignalAndInstanceNames = true;

  // ─── Signal namespace ───────────────────────────────────────────

  final Uniquifier _signalUniquifier;

  /// Sparse cache: only entries where the canonical name has been resolved.
  /// Ports whose sanitized name == logic.name may be absent (fast-path
  /// through [_portLogics] check).
  final Map<Logic, String> _signalNames = {};

  /// The set of port [Logic] objects, for O(1) port membership tests.
  final Set<Logic> _portLogics;

  // ─── Instance namespace ─────────────────────────────────────────

  final Uniquifier _instanceUniquifier = Uniquifier();

  // ─── Construction ───────────────────────────────────────────────

  Namer._({
    required Uniquifier signalUniquifier,
    required Map<Logic, String> portRenames,
    required Set<Logic> portLogics,
  })  : _signalUniquifier = signalUniquifier,
        _portLogics = portLogics {
    _signalNames.addAll(portRenames);
  }

  /// Creates a [Namer] for the given module ports.
  ///
  /// Sanitized port names are reserved in the signal namespace.  Ports
  /// whose sanitized name differs from [Logic.name] are cached immediately.
  factory Namer.forModule({
    required Map<String, Logic> inputs,
    required Map<String, Logic> outputs,
    required Map<String, Logic> inOuts,
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

    final uniquifier = Uniquifier();
    for (final name in portNames) {
      uniquifier.getUniqueName(initialName: name, reserved: true);
    }

    return Namer._(
      signalUniquifier: uniquifier,
      portRenames: portRenames,
      portLogics: portLogics,
    );
  }

  // ─── Signal availability / allocation ───────────────────────────

  bool _isSignalAvailable(String name, {bool reserved = false}) =>
      _signalUniquifier.isAvailable(name, reserved: reserved) &&
      (!uniquifySignalAndInstanceNames ||
          _instanceUniquifier.isAvailable(name));

  String _allocateUniqueSignalName(String baseName, {bool reserved = false}) {
    if (reserved) {
      if (!_isSignalAvailable(baseName, reserved: true)) {
        throw UnavailableReservedNameException(baseName);
      }

      _signalUniquifier.getUniqueName(initialName: baseName, reserved: true);
      return baseName;
    }

    var candidate = baseName;
    var suffix = 0;
    while (!_isSignalAvailable(candidate)) {
      candidate = '${baseName}_$suffix';
      suffix++;
    }

    _signalUniquifier.getUniqueName(initialName: candidate);
    return candidate;
  }

  /// Returns `true` if [name] has not yet been claimed in the signal
  /// namespace.
  bool isSignalNameAvailable(String name) => _isSignalAvailable(name);

  /// Allocates a collision-free name in the signal namespace.
  ///
  /// When [reserved] is `true`, the exact [baseName] (after sanitization)
  /// is claimed without modification; an exception is thrown if it collides.
  String allocateSignalName(String baseName, {bool reserved = false}) =>
      _allocateUniqueSignalName(
        Sanitizer.sanitizeSV(baseName),
        reserved: reserved,
      );

  // ─── Instance availability / allocation ─────────────────────────

  bool _isInstanceAvailable(String name, {bool reserved = false}) =>
      _instanceUniquifier.isAvailable(name, reserved: reserved) &&
      (!uniquifySignalAndInstanceNames || _signalUniquifier.isAvailable(name));

  /// Returns `true` if [name] has not yet been claimed in the instance
  /// namespace.
  bool isInstanceNameAvailable(String name) =>
      _instanceUniquifier.isAvailable(name);

  /// Allocates a collision-free instance name.
  ///
  /// When [reserved] is `true`, the exact [baseName] (after sanitization)
  /// is claimed without modification; an exception is thrown if it collides.
  String allocateInstanceName(String baseName, {bool reserved = false}) {
    final sanitizedBaseName = Sanitizer.sanitizeSV(baseName);

    if (!uniquifySignalAndInstanceNames) {
      return _instanceUniquifier.getUniqueName(
        initialName: sanitizedBaseName,
        reserved: reserved,
      );
    }

    if (reserved) {
      if (!_isInstanceAvailable(sanitizedBaseName, reserved: true)) {
        throw UnavailableReservedNameException(sanitizedBaseName);
      }

      return _instanceUniquifier.getUniqueName(
        initialName: sanitizedBaseName,
        reserved: true,
      );
    }

    var candidate = sanitizedBaseName;
    var suffix = 0;
    while (!_isInstanceAvailable(candidate)) {
      candidate = '${sanitizedBaseName}_$suffix';
      suffix++;
    }

    return _instanceUniquifier.getUniqueName(initialName: candidate);
  }

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

    final name = _allocateUniqueSignalName(
      base,
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

    for (final logic in preferredMergeable) {
      if (_isSignalAvailable(baseName(logic))) {
        return _nameAndCacheAll(logic, candidates);
      }
    }

    if (preferredMergeable.isNotEmpty) {
      return _nameAndCacheAll(preferredMergeable.first, candidates);
    }

    if (unpreferredMergeable.isNotEmpty) {
      final best = unpreferredMergeable
              .firstWhereOrNull((e) => _isSignalAvailable(baseName(e))) ??
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

// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_map.dart
// Extracted ModuleMap, computeComponents, and listEquals helpers so
// other handlers can reference them without circular imports.
//
// 2025 December 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/schematic_primitives.dart';

/// Compute connected-component roots for `n` items given a list of union
/// operations as index pairs. Returns a list `roots` where `roots[i]` is the
/// canonical root index for element `i`.
List<int> computeComponents(int n, Iterable<List<int>> unions,
    {List<int>? priority}) {
  final parent = List<int>.generate(n, (i) => i);
  // If a priority list is provided, ensure it has length n by
  // padding with zeros if necessary.
  var pri = priority ?? List<int>.filled(n, 0);
  if (pri.length < n) {
    pri = [...pri, ...List<int>.filled(n - pri.length, 0)];
  }
  int find(int x) {
    var r = x;
    while (parent[r] != r) {
      parent[r] = parent[parent[r]];
      r = parent[r];
    }
    return r;
  }

  void unite(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) {
      return;
    }
    // Prefer the root with higher priority; on tie, pick the smaller index.
    final pra = pri[ra];
    final prb = pri[rb];
    final winner = (pra > prb) ? ra : (prb > pra ? rb : (ra < rb ? ra : rb));
    final loser = (winner == ra) ? rb : ra;
    parent[loser] = winner;
  }

  for (final u in unions) {
    if (u.length >= 2) {
      unite(u[0], u[1]);
    }
  }

  return List<int>.generate(n, find);
}

/// Deep list equality (compare contents, not identity).
bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Minimal recursive representation of a Module hierarchy.
class ModuleMap {
  /// The Module this map was constructed from.
  final Module _module;

  /// Public accessor for the underlying Module.
  Module get module => _module;

  /// The unique name of the module this map represents.
  final String uniqueName;

  /// Maps of port logics to a list of schematic bit-ids.
  final Map<Logic, List<int>> portLogics = {};

  /// Maps of internal logics to a list of schematic bit-ids.
  final Map<Logic, List<int>> internalLogics = {};

  /// Maps of submodule unique names to their ModuleMaps.
  final Map<Module, ModuleMap> submodules = {};

  /// Set of Logic objects in this module that are considered "global".
  /// Global Logics will not have connectivity generated for them and any
  /// signals reachable from these Logics will be excluded from the
  /// ModuleMap's port/internal id assignments.
  final Set<Logic> globalLogics = {};

  /// Creates a ModuleMap for [module].
  ModuleMap(Module module,
      {bool includeInternals = false,
      bool includeChildPorts = true,
      Set<Logic>? globalLogics})
      : _module = module,
        uniqueName = module.hasBuilt ? module.uniqueInstanceName : module.name {
    var nextId = 0;
    // Collect declared ports (inputs/outputs/inouts) as the logical
    // port set for the module.
    // Initialize globalLogics set if provided.
    if (globalLogics != null) {
      this.globalLogics.addAll(globalLogics);
    }

    final portLogicsCandidates = <Logic>[
      ...module.inputs.values,
      ...module.outputs.values,
      ...module.inOuts.values
    ];

    // If global logics were provided, we want to compute the transitive set
    // of signals reachable from them (following dstConnections) so we can
    // exclude those from connectivity/id assignment.
    final reachableFromGlobals = <Logic>{};
    if (this.globalLogics.isNotEmpty) {
      final visitQueue = <Logic>[...this.globalLogics];
      while (visitQueue.isNotEmpty) {
        final cur = visitQueue.removeLast();
        if (reachableFromGlobals.contains(cur)) {
          continue;
        }
        reachableFromGlobals.add(cur);
        for (final dst in cur.dstConnections) {
          if (!reachableFromGlobals.contains(dst)) {
            visitQueue.add(dst);
          }
        }
      }
    }
    for (final logic in portLogicsCandidates) {
      // Skip any ports that are reachable from the global set; these are
      // intentionally hidden and should not have connectivity generated.
      if (reachableFromGlobals.contains(logic)) {
        continue;
      }
      final ids = List<int>.generate(logic.width, (_) => nextId++);
      portLogics[logic] = ids;
    }

    if (includeInternals) {
      final internalSignals = [
        for (final s in module.signals)
          if (!portLogics.containsKey(s)) s
      ];
      for (final sig in internalSignals) {
        // Skip any internal signals reachable from globals.
        if (reachableFromGlobals.contains(sig)) {
          continue;
        }
        final ids = List<int>.generate(sig.width, (_) => nextId++);
        internalLogics[sig] = ids;
      }

      for (final sub in module.subModules) {
        // Determine child input ports that should be considered global
        // within the child. For each input port on the child, check its
        // srcConnections and if any source is within our reachableFromGlobals
        // set (i.e., parent-side global), mark that child input as global.
        final childGlobals = <Logic>{};
        if (reachableFromGlobals.isNotEmpty) {
          for (final input in sub.inputs.values) {
            for (final src in input.srcConnections) {
              if (reachableFromGlobals.contains(src)) {
                childGlobals.add(input);
                break;
              }
            }
          }
        }

        submodules[sub] = ModuleMap(sub,
            includeInternals: includeInternals,
            includeChildPorts: includeChildPorts,
            globalLogics: childGlobals.isEmpty ? null : childGlobals);
      }
    }
  }

  /// Validates that the ModuleMap is internally consistent.
  void validate() {
    final logicToIds = <Logic, List<int>>{}
      ..addAll(portLogics)
      ..addAll(internalLogics);
    final allLogics = <Logic>[...portLogics.keys, ...internalLogics.keys];
    for (final l in allLogics) {
      if (!logicToIds.containsKey(l)) {
        throw StateError('Logic $l missing ids in module $uniqueName');
      }
    }

    final bitIdToMembers = <int, List<Logic>>{};
    for (final e in logicToIds.entries) {
      for (final bitId in e.value) {
        bitIdToMembers.putIfAbsent(bitId, () => []).add(e.key);
      }
    }

    final signals = [...portLogics.keys, ...internalLogics.keys];
    final indexOf = {for (var i = 0; i < signals.length; i++) signals[i]: i};
    final unions = <List<int>>[
      for (var i = 0; i < signals.length; i++)
        for (final conn in [
          ...signals[i].srcConnections,
          ...signals[i].dstConnections
        ])
          if (indexOf[conn] != null) [i, indexOf[conn]!]
    ];
    final roots = computeComponents(signals.length, unions);

    for (final members in bitIdToMembers.values) {
      if (members.length <= 1) {
        continue;
      }
      final root0 = roots[indexOf[members.first]!];
      for (final other in members.skip(1)) {
        final rootN = roots[indexOf[other]!];
        if (root0 != rootN) {
          final buf = StringBuffer()
            ..writeln(
                'Members ${members.first} and $other share bit-id but are '
                'not in same component in $uniqueName')
            ..writeln('Member info:');
          for (final m in members) {
            buf.writeln(
                '  - $m (ids=${logicToIds[m]}, root=${roots[indexOf[m]!]}');
          }
          throw StateError(buf.toString());
        }
      }
    }

    for (final sub in submodules.values) {
      sub.validate();
    }
  }

  /// Validates that the ModuleMap hierarchy is acyclic and unique.
  ///
  /// This implementation detects cycles by tracking `Module` instances in the
  /// current ancestor chain. Using `ModuleMap` identity alone is insufficient
  /// because different `ModuleMap` objects may be created for the same
  /// underlying `Module` when the same module is instantiated in multiple
  /// places; we want to detect the case where a module becomes a submodule of
  /// itself (directly or transitively).
  void validateHierarchy(
      {required Map<Module, List<ModuleMap>> visited,
      List<ModuleMap> hierarchy = const []}) {
    final newHierarchy = [...hierarchy, this];

    // Detect cycles by module identity: if any ancestor in the hierarchy
    // refers to the same Module object as `this.module`, we've created a
    // recursive instantiation and must error.
    if (hierarchy.any((m) => m.module == module)) {
      final loop = newHierarchy.map((m) => m.uniqueName).join('.');
      throw StateError('Module $uniqueName is a submodule of itself: $loop');
    }

    // Detect if the same Module appears in more than one place in the
    // hierarchy (different paths). Record the current path for this module
    // so that subsequent occurrences can report both locations.
    if (visited.containsKey(module)) {
      final other = visited[module]!;
      final otherStr = other.map((m) => m.uniqueName).join('.');
      final thisStr = hierarchy.map((m) => m.uniqueName).join('.');
      throw StateError(
          'Module $uniqueName exists at more than one hierarchy: $otherStr '
          'and $thisStr');
    }
    visited[module] = newHierarchy;

    for (final sub in submodules.values) {
      sub.validateHierarchy(visited: visited, hierarchy: newHierarchy);
    }
  }

  /// Validates that the ModuleMap's schematic IDs are connected properly.

  List<String> validateIdConnectivity() {
    final errors = <String>[];
    final allIds = <int, Logic>{};
    void checkIds(Logic logic, List<int> ids, String context) {
      for (final id in ids) {
        if (id < 0) {
          errors.add('$context: Logic "${logic.name}" has negative id $id');
        }
        final existing = allIds[id];
        if (existing != null && existing != logic) {
          final connected = logic.srcConnections.contains(existing) ||
              logic.dstConnections.contains(existing) ||
              existing.srcConnections.contains(logic) ||
              existing.dstConnections.contains(logic);
          if (!connected) {
            errors.add('$context: ID $id assigned to both "${logic.name}" and '
                '"${existing.name}" but they are not connected');
          }
        }
        allIds[id] = logic;
      }
    }

    for (final entry in portLogics.entries) {
      checkIds(entry.key, entry.value, uniqueName);
    }
    for (final entry in internalLogics.entries) {
      checkIds(entry.key, entry.value, '$uniqueName (internal)');
    }
    for (final sub in submodules.values) {
      errors.addAll(sub.validateIdConnectivity());
    }
    for (final sub in submodules.values) {
      var prim =
          Primitives.instance.lookupByDefinitionName(sub.module.definitionName);
      if (prim == null && sub.submodules.isEmpty) {
        prim = Primitives.instance.lookupForModule(sub.module);
      }
      if (prim == null) {
        continue;
      }
      for (final inLogic in sub.module.inputs.values) {
        if (inLogic.srcConnections.isEmpty) {
          errors.add('$uniqueName: Primitive ${sub.uniqueName} input '
              '"${inLogic.name}" has no driver');
        }
      }
    }
    return errors;
  }
}

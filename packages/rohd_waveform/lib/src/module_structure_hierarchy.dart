// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure_hierarchy.dart
// Normalizes waveform module structures to a single hierarchy root.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// A module structure paired with the hierarchy service that owns its root.
class ResolvedModuleStructure {
  /// Creates a resolved module structure.
  const ResolvedModuleStructure({
    required this.structure,
    required this.hierarchyService,
  });

  /// The normalized structure containing exactly one hierarchy root.
  final ModuleStructure structure;

  /// The hierarchy service for [structure].
  final HierarchyService hierarchyService;

  /// The root shared by [structure] and [hierarchyService].
  HierarchyOccurrence get root => hierarchyService.root;
}

/// Resolves every top-level module under one hierarchy service.
///
/// A single top-level module remains unchanged. Multiple top-level scopes are
/// placed under a synthetic `root` occurrence because [HierarchyService]
/// exposes one root.
ResolvedModuleStructure resolveModuleStructure(ModuleStructure structure) {
  if (structure.modules.isEmpty) {
    throw StateError('The waveform does not contain any module scopes.');
  }

  if (structure.modules.length == 1) {
    final root = structure.modules.single;
    final hierarchyService =
        structure.hierarchyService ?? BaseHierarchyAdapter.fromTree(root);
    return ResolvedModuleStructure(
      structure: ModuleStructure(
        metadata: structure.metadata,
        modules: [hierarchyService.root],
        hierarchyService: hierarchyService,
      ),
      hierarchyService: hierarchyService,
    );
  }

  final root = HierarchyOccurrence(
    name: 'root',
    definition: 'waveform',
    children: structure.modules,
  );
  final hierarchyService = BaseHierarchyAdapter.fromTree(root);
  return ResolvedModuleStructure(
    structure: ModuleStructure(
      metadata: structure.metadata,
      modules: [root],
      hierarchyService: hierarchyService,
    ),
    hierarchyService: hierarchyService,
  );
}

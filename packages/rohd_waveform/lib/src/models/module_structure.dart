// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure.dart
// An entity that describe the module structure of signals simulation.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:equatable/equatable.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// A class that represents the structure of a module hierarchy.
///
/// It contains metadata and a list of root modules
/// (HierarchyOccurrence objects).
/// This unified representation works with all data sources (waveform files,
/// ROHD inspector JSON, Yosys, etc.) through the adapter pattern.
class ModuleStructure extends Equatable {
  /// The metadata of the module structure.
  final MetaData metadata;

  /// The root modules in the hierarchy tree.
  /// Each HierarchyOccurrence contains its children and ports with waveform
  /// data.
  final List<HierarchyOccurrence> modules;

  /// Optional pre-built [HierarchyService] for this structure.
  ///
  /// When set (e.g. from an external hierarchy source like DevTools), this
  /// service is used directly for search and navigation instead of
  /// re-wrapping the raw [modules] nodes.  This preserves the original
  /// adapter's internal data (flat maps, connectivity, etc.) that may not
  /// be present in the [HierarchyOccurrence] objects themselves.
  final HierarchyService? hierarchyService;

  /// Creates a new instance of [ModuleStructure].
  ///
  /// Requires [metadata] and [modules] as parameters.
  const ModuleStructure({
    required this.metadata,
    required this.modules,
    this.hierarchyService,
  });

  /// Get all signal IDs in the structure (flattened from all signals).
  ///
  /// Uses [SignalOccurrence.path()] to produce unique identifiers.
  /// Includes both ports and internal signals so that the waveform viewer
  /// can select any signal in the hierarchy, not just ports.
  List<String> get allSignalIds {
    final ids = <String>[];
    void traverse(HierarchyOccurrence node) {
      for (final signal in node.signals) {
        ids.add(signal.path());
      }
      node.children.forEach(traverse);
    }

    modules.forEach(traverse);
    return ids;
  }

  /// Creates an empty module structure.
  factory ModuleStructure.empty() =>
      ModuleStructure(metadata: MetaData.empty(), modules: const []);

  /// Finds the first module that has signals (directly or in descendants).
  ///
  /// This is useful for GHW files where standard libraries may be listed
  /// as top-level modules but contain no actual signals. This method helps
  /// skip empty modules and find the actual design hierarchy.
  ///
  /// Returns null if no module with signals is found.
  HierarchyOccurrence? get firstModuleWithSignals {
    if (modules.isEmpty) {
      return null;
    }
    for (final module in modules) {
      if (module.signals.isNotEmpty) {
        return module;
      }
    }
    return null;
  }

  /// Creates a copy of this ModuleStructure with only the first real module
  /// with signals.
  ///
  /// This wraps the found module as the single root in the module list,
  /// effectively skipping empty standard library modules.
  ///
  /// Returns the original structure if no module with signals is found.
  ModuleStructure withFirstRealModule() {
    final realModule = firstModuleWithSignals;
    if (realModule == null) {
      return this;
    }
    // If the first module is already the real one, return as-is
    if (modules.first == realModule) {
      return this;
    }
    // Otherwise, wrap the real module as the single root
    return ModuleStructure(
      metadata: metadata,
      modules: [realModule],
      hierarchyService: hierarchyService,
    );
  }

  @override
  List<Object?> get props => [metadata, modules, hierarchyService];
}

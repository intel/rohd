// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlister_options.dart
// Configuration for netlist synthesis.
//
// 2026 March 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/synthesizers/netlist/leaf_cell_mapper.dart';

/// Configuration options for netlist synthesis.
///
/// The netlist synthesizer serves two main consumer flows, both configured
/// through these options:
///
/// **Flow 1 — Slim JSON** (`ModuleTree.toModuleSignalJson`):
///   Batch synthesis of the entire design, producing a lightweight
///   representation with ports, signals, and cell stubs but **no cell
///   connections**.  Used for the initial DevTools hierarchy load.
///
/// **Flow 2 — Full JSON, incremental** (`ModuleTree.moduleNetlistJson`):
///   Returns the complete netlist (with cell connections) for a single
///   module definition on demand.  Results are cached; the first call
///   may trigger a lazy `SynthBuilder` run on the requested subtree.
///
/// Both flows run the identical pipeline: `SynthBuilder` →
/// `collectModuleEntries` → `applyPostProcessingPasses`.  Flow 1
/// then strips cell connections from the cached data; Flow 2 returns
/// it verbatim.  This guarantees cell keys and wire IDs are stable
/// across both flows.
///
/// Bundles all parameters that control netlist generation into a single
/// object, making it easier to pass through call chains and to store
/// for incremental synthesis.
///
/// Example usage:
/// ```dart
/// const options = NetlisterOptions(
///   groupStructConversions: true,
///   collapseStructGroups: true,
/// );
/// final synth = NetlistSynthesizer(options: options);
/// ```
class NetlisterOptions {
  /// The leaf-cell mapper used to convert ROHD leaf modules to Yosys
  /// primitive cell types.  When `null`, [LeafCellMapper.defaultMapper]
  /// is used.
  final LeafCellMapper? leafCellMapper;

  /// When `true`, groups of `$slice` + `$concat` cells that represent
  /// structure-to-structure signal conversions are collapsed into
  /// synthetic child modules, reducing visual clutter in the netlist.
  final bool groupStructConversions;

  /// When `true` (requires [groupStructConversions] to also be `true`),
  /// the synthetic child modules created for struct conversions will have
  /// all their internal `$slice`/`$concat` cells and intermediate nets
  /// removed, leaving only a single `$buf` cell that directly connects
  /// each input port to the corresponding output port.
  final bool collapseStructGroups;

  /// When `true` (requires [groupStructConversions] to also be `true`),
  /// enables an additional grouping pass that finds `$concat` cells whose
  /// input bits all trace back through `$buf`/`$slice` chains to a
  /// contiguous sub-range of a single source bus.
  final bool groupMaximalSubsets;

  /// When `true` (requires [groupStructConversions] to also be `true`),
  /// enables an additional pass that finds `$concat` cells where a
  /// contiguous run of input ports trace back through `$buf`/`$slice`
  /// chains to a contiguous sub-range of a single source bus.
  final bool collapseConcats;

  /// When `true`, dead-cell elimination is performed after aliasing to
  /// remove cells whose inputs are entirely undriven or whose outputs
  /// are entirely unconsumed.
  final bool enableDCE;

  /// When `true`, the synthesizer produces "slim" output: the full
  /// synthesis pipeline runs (including all post-processing passes),
  /// but cell connection maps are stripped from the result.
  /// Netnames and ports are still emitted with full wire-ID fidelity,
  /// so a subsequent full-mode synthesis of the same module will
  /// produce compatible wire IDs.
  final bool slimMode;

  /// Creates a [NetlisterOptions] with the given configuration.
  ///
  /// All parameters have sensible defaults matching the current
  /// netlist synthesizer behaviour.
  const NetlisterOptions({
    this.leafCellMapper,
    this.groupStructConversions = false,
    this.collapseStructGroups = false,
    this.groupMaximalSubsets = false,
    this.collapseConcats = false,
    this.enableDCE = true,
    this.slimMode = false,
  });
}

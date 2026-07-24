// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_options.dart
// Configuration for netlist synthesis.
//
// 2026 March 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart' hide SynthModuleStopPolicy;
import 'package:rohd/src/synthesizers/netlist/netlist_cell_mapper.dart';
import 'package:rohd/src/synthesizers/utilities/synth_module_stop_policy.dart';

/// Configuration options for netlist synthesis.
///
/// The netlist synthesizer serves two main consumer flows, both configured
/// through these options:
///
/// **Flow 1 — Slim JSON** (`NetlistService.slimJson`):
///   Batch synthesis of the entire design, producing a lightweight
///   representation with ports, signals, and cell stubs but **no cell
///   connections**.  Used for the initial DevTools hierarchy load.
///
/// **Flow 2 — Full JSON, incremental** (`NetlistService.moduleJson`):
///   Returns the complete netlist (with cell connections) for a single
///   module definition on demand.  Results are cached; the first call
///   may trigger a lazy `SynthBuilder` run on the requested subtree.
///
/// Both flows retain complete per-module synthesis results. Flow 1 skips cell
/// connection copying while collecting the emitted JSON projection. This keeps
/// slim output lightweight while guaranteeing a later expanded request has the
/// same cell keys, wire IDs, and connectivity as an initially expanded request.
///
/// Bundles all parameters that control netlist generation into a single
/// object, making it easier to pass through call chains and to store
/// for incremental synthesis.
///
/// Example usage:
/// ```dart
/// const options = NetlistOptions(
///   collapseTransparentClusters: true,
/// );
/// final synth = NetlistSynthesizer(options: options);
/// ```
class NetlistOptions {
  /// The policy used to decide which modules stop hierarchy traversal and are
  /// emitted as cells in their parent instead of as separate module
  /// definitions. When `null`, [SynthModuleStopPolicy.netlist] is used.
  ///
  /// When this is provided, it owns the complete stopping policy and
  /// [leafModuleTypes] is ignored.
  final SynthModuleStopPolicy? moduleStopPolicy;

  /// Exact [Module.runtimeType]s that should stop netlist hierarchy traversal
  /// and be emitted as cells in their parent. Defaults to [FlipFlop], which
  /// contains internal sequential submodules but should be emitted as a `$dff`
  /// netlist cell.
  final List<Type> leafModuleTypes;

  /// The netlist-internal mapper used to convert selected leaf modules to
  /// Yosys primitive cell types. When `null`, each synthesizer creates its own
  /// mapper containing the default handlers.
  @internal
  final NetlistCellMapper? netlistCellMapper;

  /// When `true`, a single unified pass finds connected components of
  /// all transparent cells (`$buf`, `$slice`, `$concat`,
  /// `$struct_unpack`, `$struct_pack`), traces each cluster's output
  /// bits back to their ultimate source bits, and replaces every
  /// multi-cell cluster with a direct `$buf`.  This subsumes all of
  /// the individual collapse passes above.
  final bool collapseTransparentClusters;

  /// When `true`, dead-cell elimination is performed after aliasing to
  /// remove cells whose inputs are entirely undriven or whose outputs
  /// are entirely unconsumed.
  final bool enableDCE;

  /// When `true`, the synthesizer produces "slim" output: cell connection maps
  /// are not copied into the emitted JSON projection. Netnames and ports are
  /// still emitted with full wire-ID fidelity, while per-module synthesis
  /// results retain complete connectivity.
  final bool slimMode;

  /// When `true`, contiguous ascending runs of ≥3 integer bit IDs in
  /// `bits` arrays and cell `connections` arrays are replaced with
  /// `"start:end"` range strings (e.g. `[52, 53, 54, 55]` → `["52:55"]`).
  ///
  /// This is backward-compatible: Yosys-format arrays already mix
  /// integers with constant strings `"0"` and `"1"`.  Parsers can
  /// detect range strings by the presence of `:`.
  final bool compressBitRanges;

  /// When `true`, the JSON output uses no indentation (compact form).
  /// When `false` (default), the JSON is pretty-printed with two-space
  /// indentation.
  final bool compactJson;

  /// Creates a [NetlistOptions] with the given configuration.
  ///
  /// All parameters have sensible defaults matching the current
  /// netlist synthesizer behaviour.
  const NetlistOptions({
    this.moduleStopPolicy,
    this.leafModuleTypes = const [FlipFlop],
    this.netlistCellMapper,
    this.collapseTransparentClusters = false,
    this.enableDCE = true,
    this.slimMode = false,
    this.compressBitRanges = false,
    this.compactJson = false,
  });
}

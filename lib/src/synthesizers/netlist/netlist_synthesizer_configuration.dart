// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_synthesizer_configuration.dart
// Configuration for netlist synthesis.
//
// 2026 March 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_cell_mapper.dart';
export '../utilities/synth_module_stop_policy.dart';

/// Configuration for netlist synthesis.
///
/// The netlist synthesizer serves two main consumer flows, both configured
/// through this configuration:
///
/// **Flow 1 — Slim JSON** ([NetlistSynthesizer.synthesizeToJson] with
/// `slimMode: true`):
///   Batch synthesis of the entire design, producing a lightweight
///   representation with ports, signals, and cell stubs but **no cell
///   connections**.  Used for the initial DevTools hierarchy load.
///
/// **Flow 2 — Full JSON** ([NetlistSynthesizer.synthesizeToJson] with
/// `slimMode: false`):
///   Synthesizes the entire design with complete cell connections.
///
/// [NetlistService] exposes these projections through [NetlistService.slimJson]
/// and [NetlistService.moduleJson], preserving a shared netlist representation
/// across the two flows.
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
/// final synth = NetlistSynthesizer();
/// ```
class NetlistSynthesizerConfiguration {
  /// The policy used to decide which modules stop hierarchy traversal and are
  /// emitted as cells in their parent instead of as separate module
  /// definitions. When `null`, [SynthModuleStopPolicy.netlist] is used.
  ///
  /// When this is provided, it owns the complete stopping policy and
  /// [leafModulePredicate] is ignored.
  final SynthModuleStopPolicy? moduleStopPolicy;

  /// Determines which modules should stop netlist hierarchy traversal and be
  /// emitted as cells in their parent.
  ///
  /// Defaults to matching [FlipFlop] and its subclasses, which contain internal
  /// sequential submodules but should be emitted as `$dff` netlist cells.
  final SynthModuleLeafPredicate leafModulePredicate;

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
  @internal
  final bool collapseTransparentClusters;

  /// When `true`, dead-cell elimination is performed after aliasing to
  /// remove cells whose inputs are entirely undriven or whose outputs
  /// are entirely unconsumed.
  @internal
  final bool enableDeadCellElimination;

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
  @internal
  final bool compressBitRanges;

  /// When `true`, the JSON output uses no indentation (compact form).
  /// When `false` (default), the JSON is pretty-printed with two-space
  /// indentation.
  final bool compactJson;

  /// Creates a configuration for netlist synthesis.
  const NetlistSynthesizerConfiguration({
    this.moduleStopPolicy,
    this.leafModulePredicate = _isFlipFlop,
    this.netlistCellMapper,
    @visibleForTesting this.collapseTransparentClusters = false,
    @visibleForTesting this.enableDeadCellElimination = true,
    this.slimMode = false,
    @visibleForTesting this.compressBitRanges = false,
    this.compactJson = false,
  });
}

bool _isFlipFlop(Module module) => module is FlipFlop;

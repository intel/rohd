// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_options.dart
// Configuration for netlist synthesis.
//
// 2026 March 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/synthesizers/netlist/leaf_cell_mapper.dart';

/// The current format version for netlist JSON produced by ROHD.
const String netlistFormatVersion = '0.0.5';

/// Configuration options for netlist synthesis.
///
/// The netlist synthesizer serves two main consumer flows, both configured
/// through these options:
///
/// **Flow 1 — Slim JSON** ([NetlistOptions.slimMode]):
///   Batch synthesis of the entire design, producing a lightweight
///   representation with ports, signals, and cell stubs but **no cell
///   connections**.  Used for the initial DevTools hierarchy load.
///
/// **Flow 2 — Full JSON, incremental** (`NetlistSynthesizer.synthesizeToJson`):
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
/// const options = NetlistOptions(
///   collapseTransparentClusters: true,
/// );
/// final synth = NetlistSynthesizer(options: options);
/// ```
class NetlistOptions {
  /// The leaf-cell mapper used to convert ROHD leaf modules to Yosys
  /// primitive cell types.  When `null`, [LeafCellMapper.defaultMapper]
  /// is used.
  final LeafCellMapper? leafCellMapper;

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

  /// When `true`, the synthesizer produces "slim" output: the full
  /// synthesis pipeline runs (including all post-processing passes),
  /// but cell connection maps are stripped from the result.
  /// Netnames and ports are still emitted with full wire-ID fidelity,
  /// so a subsequent full-mode synthesis of the same module will
  /// produce compatible wire IDs.
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
    this.leafCellMapper,
    this.collapseTransparentClusters = false,
    this.enableDCE = true,
    this.slimMode = false,
    this.compressBitRanges = false,
    this.compactJson = false,
  });
}

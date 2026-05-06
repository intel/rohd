// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_synthesis_result.dart
// A simple SynthesisResult that holds netlist data for one module.
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';

/// A [SynthesisResult] that holds the netlist representation of a single
/// module level: its ports, cells, and netnames.
class NetlistSynthesisResult extends SynthesisResult {
  /// The ports map: name → {direction, bits}.
  final Map<String, Map<String, Object?>> ports;

  /// The cells map: instance name → cell data.
  final Map<String, Map<String, Object?>> cells;

  /// The netnames map: net name → {bits, attributes}.
  final Map<String, Object?> netnames;

  /// Attributes for this module (e.g., top marker).
  final Map<String, Object?> attributes;

  /// Cached JSON string for comparison and output.
  late final String _cachedJson = _buildJson();

  /// Creates a [NetlistSynthesisResult] for [module].
  NetlistSynthesisResult(
    super.module,
    super.getInstanceTypeOfModule, {
    required this.ports,
    required this.cells,
    required this.netnames,
    this.attributes = const {},
  });

  String _buildJson() {
    final moduleEntry = <String, Object?>{
      'attributes': attributes,
      'ports': ports,
      'cells': cells,
      'netnames': netnames,
    };
    return const JsonEncoder().convert(moduleEntry);
  }

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is NetlistSynthesisResult && _cachedJson == other._cachedJson;

  @override
  int get matchHashCode => _cachedJson.hashCode;

  @override
  @Deprecated('Use `toSynthFileContents()` instead.')
  String toFileContents() => toSynthFileContents().first.contents;

  @override
  List<SynthFileContents> toSynthFileContents() {
    final typeName = instanceTypeName;
    final moduleEntry = <String, Object?>{
      'attributes': attributes,
      'ports': ports,
      'cells': cells,
      'netnames': netnames,
    };
    final contents = const JsonEncoder.withIndent('  ').convert({
      'creator': 'NetlistSynthesizer (rohd)',
      'modules': {typeName: moduleEntry},
    });
    return [
      SynthFileContents(
        name: '$typeName.rohd.json',
        description: 'netlist for $typeName',
        contents: contents,
      ),
    ];
  }
}

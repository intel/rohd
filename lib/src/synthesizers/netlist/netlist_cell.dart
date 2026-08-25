// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_cell.dart
// Typed representation of a serialized netlist cell.
//
// 2026 August 24
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_port_direction.dart';

/// The ROHD construct that produced a netlist cell.
@internal
enum NetlistCellOrigin {
  module,
  arraySlice,
  arrayConcat,
  outputArrayConcat,
  structureSlice,
  structurePack,
  structureUnpack;

  /// Whether this cell was introduced to represent synthesized structure.
  bool get isSynthetic => this != module;
}

/// A cell in a synthesized netlist.
@internal
class NetlistCell {
  /// Whether consumers should hide this cell's name.
  final int hideName;

  /// The Yosys cell type or module definition name.
  final String type;

  /// Parameters configuring the cell.
  final Map<String, Object?> parameters;

  /// Attributes attached to the cell.
  final Map<String, Object?> attributes;

  /// Directions of the cell's ports.
  final Map<String, NetlistPortDirection> portDirections;

  /// Bits connected to each cell port.
  final Map<String, List<Object>> connections;

  /// The ROHD construct that produced this cell.
  final NetlistCellOrigin origin;

  /// Creates a netlist cell.
  const NetlistCell({
    required this.type,
    required this.portDirections,
    required this.connections,
    this.parameters = const {},
    this.attributes = const {},
    this.hideName = 0,
    this.origin = NetlistCellOrigin.module,
  });

  /// Whether [json] represents a cell with [origin].
  static bool hasOrigin(Map<String, Object?> json, NetlistCellOrigin origin) =>
      json['synthetic_origin'] == origin.name;

  /// Serializes this cell to the Yosys-compatible JSON structure.
  Map<String, Object?> toJson() => {
        'hide_name': hideName,
        'type': type,
        'parameters': parameters,
        'attributes': attributes,
        if (origin.isSynthetic) ...{
          'is_synthetic': true,
          'synthetic_origin': origin.name,
        },
        'port_directions': serializePortDirections(portDirections),
        'connections': connections,
      };
}

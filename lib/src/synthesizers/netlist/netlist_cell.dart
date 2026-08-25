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

  /// Creates a netlist cell.
  const NetlistCell({
    required this.type,
    required this.portDirections,
    required this.connections,
    this.parameters = const {},
    this.attributes = const {},
    this.hideName = 0,
  });

  /// Serializes this cell to the Yosys-compatible JSON structure.
  Map<String, Object?> toJson() => {
        'hide_name': hideName,
        'type': type,
        'parameters': parameters,
        'attributes': attributes,
        'port_directions': serializePortDirections(portDirections),
        'connections': connections,
      };
}

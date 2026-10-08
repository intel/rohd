// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_port_direction.dart
// Type-safe netlist port directions and JSON serialization.
//
// 2026 August 24
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';

/// A port direction while constructing a netlist.
@internal
enum NetlistPortDirection {
  input,
  output,
  inout,
}

/// Converts typed [directions] to the strings required by Yosys JSON.
@internal
Map<String, String> serializePortDirections(
  Map<String, NetlistPortDirection> directions,
) =>
    {
      for (final entry in directions.entries) entry.key: entry.value.name,
    };

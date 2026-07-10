// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

//
// netlist_validation.dart
// Structural validation utilities for emitted netlists.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';

/// Graph queries and structural checks for an emitted module netlist.
@internal
class NetlistValidation {
  NetlistValidation._();

  /// Collects module-port and cell-connection bits with matching directions.
  static Set<int> connectedBits(
    Map<String, Map<String, Object?>> ports,
    Map<String, Map<String, Object?>> cells, {
    required Set<String> portDirections,
    required String cellDirection,
  }) =>
      <int>{
        ...ports.values
            .where((port) => portDirections.contains(port['direction']))
            .expand((port) => (port['bits'] as List?) ?? const [])
            .whereType<int>(),
        ...cells.values.expand((cell) {
          final connections =
              cell['connections'] as Map<String, dynamic>? ?? const {};
          final directions =
              cell['port_directions'] as Map<String, dynamic>? ?? const {};
          return connections.entries
              .where((port) => directions[port.key] == cellDirection)
              .expand((port) => (port.value as List?) ?? const [])
              .whereType<int>();
        }),
      };

  /// Reports disconnected cells and floating constants in debug builds.
  static void validate(
    Map<String, Map<String, Object?>> ports,
    Map<String, Map<String, Object?>> cells,
    String moduleName,
  ) {
    final consumedBits = connectedBits(
      ports,
      cells,
      portDirections: const {'output', 'inout'},
      cellDirection: 'input',
    );
    const transparentTypes = {
      r'$buf',
      r'$slice',
      r'$concat',
      r'$struct_unpack',
      r'$struct_pack',
    };

    for (final entry in cells.entries) {
      final cell = entry.value;
      final type = cell['type'] as String? ?? '';
      if (transparentTypes.contains(type) || type == r'$const') {
        continue;
      }
      final outputBits = _cellBits(cell, 'output');
      if (outputBits.isNotEmpty && !outputBits.any(consumedBits.contains)) {
        // ignore: avoid_print
        print(
          '[netlist-validate] WARNING: $moduleName: '
          'cell "${entry.key}" (type: $type) has no consumed outputs '
          '— fully disconnected logic gate',
        );
      }
    }

    for (final entry in cells.entries.where(
      (entry) => entry.value['type'] == r'$const',
    )) {
      final outputBits = _cellBits(entry.value, 'output');
      if (outputBits.isNotEmpty && !outputBits.any(consumedBits.contains)) {
        // ignore: avoid_print
        print(
          '[netlist-validate] WARNING: $moduleName: '
          r'$const cell "${entry.key}" drives wires consumed by nothing '
          '— floating constant',
        );
      }
    }
  }

  static List<int> _cellBits(
    Map<String, Object?> cell,
    String direction,
  ) {
    final connections = cell['connections'] as Map<String, dynamic>?;
    final directions = cell['port_directions'] as Map<String, dynamic>?;
    if (connections == null || directions == null) {
      return const [];
    }
    return connections.entries
        .where((port) => directions[port.key] == direction)
        .expand((port) => (port.value as List?) ?? const [])
        .whereType<int>()
        .toList();
  }
}

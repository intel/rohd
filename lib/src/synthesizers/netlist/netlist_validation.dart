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
  /// Prevents construction of this static utility class.
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

  /// Reports disconnected cells, floating constants, and shorted wires.
  static List<String> validate(
    Map<String, Map<String, Object?>> ports,
    Map<String, Map<String, Object?>> cells,
    String moduleName, {
    Map<String, Object?>? netnames,
    bool throwOnMultipleDrivers = false,
    bool printWarnings = true,
  }) {
    final warnings = <String>[];
    final multipleDriverWarnings = <String>[];

    void report(String message, {bool multipleDriver = false}) {
      warnings.add(message);
      if (multipleDriver) {
        multipleDriverWarnings.add(message);
      }
      if (printWarnings) {
        // ignore: avoid_print
        print(message);
      }
    }

    final consumedBits = connectedBits(
      ports,
      cells,
      portDirections: const {'output', 'inout'},
      cellDirection: 'input',
    );
    final driversByBit = _driversByBit(ports, cells);
    const transparentTypes = {
      r'$buf',
      r'$slice',
      r'$concat',
      r'$struct_unpack',
      r'$struct_pack',
    };

    for (final entry in driversByBit.entries) {
      if (entry.value.length <= 1) {
        continue;
      }
      report(
        '[netlist-validate] WARNING: $moduleName: '
        'wire bit ${entry.key} has multiple drivers: '
        '${entry.value.join(', ')}',
        multipleDriver: true,
      );
    }

    if (netnames != null) {
      for (final entry in netnames.entries) {
        final netname = entry.value;
        if (netname is! Map<String, Object?>) {
          continue;
        }
        final logicType = netname['logic_type'];
        if (logicType is! Map ||
            (logicType['arrayDims'] is! List && logicType['fields'] is! List)) {
          continue;
        }
        final bits = (netname['bits'] as List?)?.whereType<int>() ?? const [];
        final aggregateDrivers = <String>{
          for (final bit in bits) ...driversByBit[bit] ?? const <String>[],
        };
        if (aggregateDrivers.length <= 1) {
          continue;
        }
        report(
          '[netlist-validate] WARNING: $moduleName: '
          'aggregate net "${entry.key}" is reached from multiple drivers: '
          '${aggregateDrivers.join(', ')}',
          multipleDriver: true,
        );
      }
    }

    if (throwOnMultipleDrivers && multipleDriverWarnings.isNotEmpty) {
      throw StateError(
        'Netlist validation failed for $moduleName: '
        '${multipleDriverWarnings.length} multiple-driver wire bit(s) found.\n'
        '${multipleDriverWarnings.join('\n')}',
      );
    }

    for (final entry in cells.entries) {
      final cell = entry.value;
      final type = cell['type'] as String? ?? '';
      if (transparentTypes.contains(type) || type == r'$const') {
        continue;
      }
      final outputBits = _cellBits(cell, 'output');
      if (outputBits.isNotEmpty && !outputBits.any(consumedBits.contains)) {
        report(
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
        report(
          '[netlist-validate] WARNING: $moduleName: '
          r'$const cell "${entry.key}" drives wires consumed by nothing '
          '— floating constant',
        );
      }
    }

    return warnings;
  }

  /// Collects the port and cell output drivers for each integer bit ID.
  static Map<int, List<String>> _driversByBit(
    Map<String, Map<String, Object?>> ports,
    Map<String, Map<String, Object?>> cells,
  ) {
    final drivers = <int, List<String>>{};

    void addDriver(int bit, String driver) =>
        (drivers[bit] ??= <String>[]).add(driver);

    for (final entry in ports.entries) {
      final direction = entry.value['direction'] as String?;
      if (direction != 'input' && direction != 'inout') {
        continue;
      }
      for (final bit in (entry.value['bits'] as List?) ?? const []) {
        if (bit is int) {
          addDriver(bit, 'port ${entry.key} ($direction)');
        }
      }
    }

    for (final entry in cells.entries) {
      final connections = entry.value['connections'] as Map<String, dynamic>?;
      final directions =
          entry.value['port_directions'] as Map<String, dynamic>?;
      if (connections == null || directions == null) {
        continue;
      }
      final type = entry.value['type'] as String? ?? 'unknown';
      for (final port in connections.entries) {
        final direction = directions[port.key] as String?;
        if (direction != 'output' && direction != 'inout') {
          continue;
        }
        for (final bit in (port.value as List?) ?? const []) {
          if (bit is int) {
            addDriver(bit, 'cell ${entry.key}.${port.key} ($type)');
          }
        }
      }
    }

    return drivers;
  }

  /// Returns integer bits connected to ports with the requested [direction].
  static List<int> _cellBits(Map<String, Object?> cell, String direction) {
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

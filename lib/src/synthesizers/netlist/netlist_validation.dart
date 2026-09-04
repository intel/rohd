// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_validation.dart
// Structural validation utilities for emitted netlists.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/src/exceptions/synth_exception.dart';

typedef _NetlistDriver = ({String description, bool isTriState});

/// Graph queries and structural checks for an emitted module netlist.
@internal
class NetlistValidation {
  static const _nonDrivingAliasTypes = {
    r'$slice',
    r'$concat',
    r'$struct_unpack',
    r'$struct_pack',
  };

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

  /// Throws [NetlistValidationException] if the netlist has structural errors.
  static void validate(
    Map<String, Map<String, Object?>> ports,
    Map<String, Map<String, Object?>> cells,
    String moduleName, {
    Map<String, Object?>? netnames,
  }) {
    final issues = <NetlistValidationIssue>[];

    final driversByBit = _driversByBit(ports, cells);

    for (final entry in driversByBit.entries) {
      if (!_hasConflictingDrivers(entry.value)) {
        continue;
      }
      final drivers = entry.value.map((driver) => driver.description).toList();
      issues.add(NetlistValidationIssue(
        'wire bit ${entry.key} has multiple drivers: '
        '${drivers.join(', ')}',
        wireBit: entry.key,
        drivers: drivers,
      ));
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
        final aggregateDrivers = <_NetlistDriver>{
          for (final bit in bits)
            ...driversByBit[bit] ?? const <_NetlistDriver>[],
        };
        if (!_hasConflictingDrivers(aggregateDrivers)) {
          continue;
        }
        final drivers =
            aggregateDrivers.map((driver) => driver.description).toList();
        issues.add(NetlistValidationIssue(
          'aggregate net "${entry.key}" is reached from multiple drivers: '
          '${drivers.join(', ')}',
          netname: entry.key,
          drivers: drivers,
        ));
      }
    }

    if (issues.isNotEmpty) {
      throw NetlistValidationException(moduleName, issues);
    }
  }

  /// Collects the port and cell output drivers for each integer bit ID.
  static Map<int, List<_NetlistDriver>> _driversByBit(
    Map<String, Map<String, Object?>> ports,
    Map<String, Map<String, Object?>> cells,
  ) {
    final drivers = <int, List<_NetlistDriver>>{};

    void addDriver(int bit, String description, {bool isTriState = false}) =>
        (drivers[bit] ??= <_NetlistDriver>[])
            .add((description: description, isTriState: isTriState));

    for (final entry in ports.entries) {
      final direction = entry.value['direction'] as String?;
      if (direction != 'input') {
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
      if (_nonDrivingAliasTypes.contains(type)) {
        continue;
      }
      for (final port in connections.entries) {
        final direction = directions[port.key] as String?;
        final isTriStateOutput = type == r'$tribuf' &&
            (direction == 'output' || direction == 'inout');
        if (direction != 'output' && !isTriStateOutput) {
          continue;
        }
        for (final bit in (port.value as List?) ?? const []) {
          if (bit is int) {
            addDriver(
              bit,
              'cell ${entry.key}.${port.key} ($type)',
              isTriState: isTriStateOutput,
            );
          }
        }
      }
    }

    return drivers;
  }

  static bool _hasConflictingDrivers(Iterable<_NetlistDriver> drivers) {
    var count = 0;
    var allTriState = true;
    for (final driver in drivers) {
      count++;
      allTriState &= driver.isTriState;
    }
    return count > 1 && !allTriState;
  }
}

/// A structural netlist validation failure.
@internal
class NetlistValidationException extends SynthException {
  /// The module containing the structural errors.
  final String moduleName;

  /// The structural errors found in [moduleName].
  final List<NetlistValidationIssue> issues;

  /// Creates a validation exception for [moduleName].
  NetlistValidationException(
      this.moduleName, Iterable<NetlistValidationIssue> issues)
      : issues = List.unmodifiable(issues),
        super('Netlist validation failed for $moduleName.');

  @override
  String toString() => 'Netlist validation failed for $moduleName: '
      '${issues.length} issue(s) found.\n'
      '${issues.join('\n')}';
}

/// A structural problem found while validating an emitted netlist.
@internal
class NetlistValidationIssue {
  /// A human-readable explanation of the structural problem.
  final String description;

  /// The affected wire bit, when the problem concerns one bit.
  final int? wireBit;

  /// The affected aggregate net name, when applicable.
  final String? netname;

  /// The drivers involved in the problem, when applicable.
  final List<String> drivers;

  /// Creates a structural validation issue.
  NetlistValidationIssue(
    this.description, {
    this.wireBit,
    this.netname,
    Iterable<String> drivers = const [],
  }) : drivers = List.unmodifiable(drivers);

  @override
  String toString() => description;
}

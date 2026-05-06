// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_service.dart
// Service wrapper for netlist synthesis.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';

/// A service that wraps netlist (Yosys JSON) synthesis of a [Module]
/// hierarchy.
///
/// Provides access to the full hierarchy JSON and per-module JSON with
/// lazy caching, and optionally registers with [ModuleServices] for
/// DevTools inspection.
///
/// Example:
/// ```dart
/// final dut = MyModule(...);
/// await dut.build();
/// final netlist = await NetlistService.create(dut);
///
/// // Full hierarchy JSON:
/// print(netlist.toJson());
///
/// // Single module (lazy, cached):
/// print(netlist.moduleJson('FilterChannel'));
/// ```
class NetlistService {
  /// The top-level [Module] being synthesized.
  final Module module;

  /// The [NetlistSynthesizer] used for synthesis.
  final NetlistSynthesizer synthesizer;

  /// The underlying [SynthBuilder].
  late final SynthBuilder synthBuilder;

  /// The combined JSON string for the full hierarchy.
  late final String _fullJson;

  /// Cached per-module JSON, keyed by definition name.
  final Map<String, String> _moduleJsonCache = {};

  /// The parsed modules map from the combined JSON.
  late final Map<String, dynamic> _modulesMap;

  NetlistService._(this.module, this.synthesizer, this._fullJson) {
    final decoded = jsonDecode(_fullJson) as Map<String, dynamic>;
    _modulesMap =
        (decoded['modules'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// Creates a [NetlistService] for [module].
  ///
  /// [module] must already be built.  Set [register] to `true` (the
  /// default) to register this service with [ModuleServices] for
  /// DevTools access.
  ///
  /// The [options] parameter controls netlist synthesis behaviour;
  /// see [NetlistOptions] for details.
  static Future<NetlistService> create(
    Module module, {
    NetlistOptions options = const NetlistOptions(),
    bool register = true,
  }) async {
    if (!module.hasBuilt) {
      throw Exception('Module must be built before creating NetlistService. '
          'Call build() first.');
    }

    final synthesizer = NetlistSynthesizer(options: options);
    final json = await synthesizer.synthesizeToJson(module);

    final service = NetlistService._(module, synthesizer, json);

    if (register) {
      ModuleServices.instance.netlistService = service;
    }

    return service;
  }

  /// Returns the full netlist hierarchy as a JSON string.
  String toJson() => _fullJson;

  /// Returns the netlist JSON for a single module [definitionName].
  ///
  /// If the module is not found, returns a JSON error object.
  String moduleJson(String definitionName) =>
      _moduleJsonCache.putIfAbsent(definitionName, () {
        final modData = _modulesMap[definitionName];
        if (modData == null) {
          return jsonEncode(<String, String>{
            'status': 'not_found',
            'reason': 'module "$definitionName" not in netlist',
          });
        }
        return jsonEncode(<String, Object?>{
          'creator': 'ROHD netlist synthesizer',
          'modules': <String, Object?>{definitionName: modData},
        });
      });

  /// Returns the set of module definition names in the netlist.
  Set<String> get moduleNames => _modulesMap.keys.toSet();

  /// Read-only access to the parsed modules map.
  ///
  /// Each key is a definition name and each value is the Yosys-style
  /// module descriptor containing `ports`, `cells`, and `netnames`.
  Map<String, dynamic> get synthesizedModules =>
      Map<String, dynamic>.unmodifiable(_modulesMap);

  /// Cached slim JSON (lazy).
  String? _slimJsonCache;

  /// Returns a slim netlist JSON string — same structure as [toJson] but
  /// with cell `connections` stripped.
  ///
  /// The slim representation preserves ports, cells (type + port_directions
  /// + port_widths), and netnames so the DevTools extension can render the
  /// hierarchy and signal tree without the full connectivity payload.
  /// Full per-module connectivity is fetched on demand via [moduleJson].
  String get slimJson => _slimJsonCache ??= _buildSlimJson();

  String _buildSlimJson() {
    final slimModules = <String, dynamic>{};
    for (final entry in _modulesMap.entries) {
      final mod = entry.value as Map<String, dynamic>;
      final cells = mod['cells'] as Map<String, dynamic>? ?? {};
      final slimCells = <String, dynamic>{};
      for (final cellEntry in cells.entries) {
        final cell = cellEntry.value as Map<String, dynamic>;
        // Compute per-port widths from connections (bit-array lengths).
        final conns = cell['connections'] as Map<String, dynamic>?;
        final portWidths = <String, int>{};
        if (conns != null) {
          for (final c in conns.entries) {
            final bits = c.value;
            if (bits is List) {
              portWidths[c.key] = bits.length;
            }
          }
        }
        slimCells[cellEntry.key] = <String, dynamic>{
          'hide_name': cell['hide_name'] ?? 0,
          'type': cell['type'],
          'parameters': cell['parameters'] ?? <String, dynamic>{},
          'attributes': cell['attributes'] ?? <String, dynamic>{},
          'port_directions': cell['port_directions'] ?? <String, dynamic>{},
          if (portWidths.isNotEmpty) 'port_widths': portWidths,
          // connections intentionally omitted → slim
        };
      }

      // Determine which module-level ports have internal connectivity.
      final ports = mod['ports'] as Map<String, dynamic>? ?? {};
      final slimPorts = <String, dynamic>{};
      final cellConnectedBits = <int>{};
      for (final cellEntry in cells.values) {
        final cell = cellEntry as Map<String, dynamic>;
        final conns = cell['connections'] as Map<String, dynamic>?;
        if (conns == null) {
          continue;
        }
        for (final bits in conns.values) {
          if (bits is List) {
            for (final b in bits) {
              if (b is int) {
                cellConnectedBits.add(b);
              }
            }
          }
        }
      }
      for (final portEntry in ports.entries) {
        final portData = portEntry.value as Map<String, dynamic>;
        final bits = portData['bits'] as List?;
        var connected = false;
        if (bits != null) {
          for (final b in bits) {
            if (b is int && cellConnectedBits.contains(b)) {
              connected = true;
              break;
            }
          }
        }
        slimPorts[portEntry.key] = <String, dynamic>{
          ...portData,
          if (connected) 'connected': true,
        };
      }

      final netnames = mod['netnames'] as Map<String, dynamic>? ?? {};

      slimModules[entry.key] = <String, dynamic>{
        'attributes': <String, dynamic>{
          ...(mod['attributes'] as Map<String, dynamic>? ?? {}),
          'original_signal_count': netnames.length,
          'original_cell_count': slimCells.length,
        },
        'ports': slimPorts,
        'cells': slimCells,
        'netnames': netnames,
      };
    }

    final rootName = module.hasBuilt ? module.uniqueInstanceName : module.name;

    return jsonEncode(<String, dynamic>{
      'netlist': <String, dynamic>{
        'creator': 'ROHD NetlistService (slim)',
        'rootInstanceName': rootName,
        'modules': slimModules,
      },
    });
  }
}

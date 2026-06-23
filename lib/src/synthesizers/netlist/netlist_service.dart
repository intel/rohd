// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_service.dart
// Service wrapper for netlist synthesis.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

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
/// final netlist = NetlistService(dut);
///
/// // Full hierarchy JSON:
/// print(netlist.json);
///
/// // Single module (lazy, cached):
/// print(netlist.moduleJson('FilterChannel'));
/// ```
class NetlistService extends OutputService {
  /// The current format version for netlist JSON produced by this service.
  static const String formatVersion = '0.0.5';

  /// The most recently registered [NetlistService], or `null`.
  static NetlistService? current;

  /// The top-level [Module] being synthesized.
  @override
  final Module module;

  /// The default location written by [write], or `null`.
  @override
  final String? outputPath;

  /// Whether [write] emits multiple files. Netlist output is a single JSON
  /// document, so this is always `false`.
  @override
  bool get multiFile => false;

  /// The [NetlistSynthesizer] used for synthesis.
  late final NetlistSynthesizer synthesizer;

  /// The underlying [SynthBuilder].
  late final SynthBuilder synthBuilder;

  /// The combined JSON string for the full hierarchy.
  late final String _fullJson;

  /// Cached per-module JSON, keyed by definition name.
  final Map<String, String> _moduleJsonCache = {};

  /// The parsed modules map from the combined JSON.
  late final Map<String, dynamic> _modulesMap;

  /// The package root directory used for FLC trace injection.
  ///
  /// When non-null, downstream trace-enabled branches use this path to embed
  /// `rohd.src_trace` attributes in the netlist JSON.
  late final String? packageRoot;

  /// Creates a netlist service for a built [module].
  ///
  /// Uses [options] for netlist synthesis configuration and optionally
  /// [register]s this instance with [ModuleServices] for DevTools lookup.
  NetlistService(
    this.module, {
    NetlistOptions options = const NetlistOptions(),
    String? packageRoot,
    bool register = true,
    this.outputPath,
  }) {
    if (!module.hasBuilt) {
      throw Exception(
        'Module must be built before creating NetlistService. '
        'Call build() first.',
      );
    }

    final effectiveRoot = packageRoot;
    synthesizer = NetlistSynthesizer(options: options);
    this.packageRoot = effectiveRoot;
    synthBuilder = SynthBuilder(module, synthesizer);
    _fullJson = synthesizer.synthesizeToJson(
      module,
      packageRoot: effectiveRoot,
    );

    final decoded = jsonDecode(_fullJson) as Map<String, dynamic>;
    _modulesMap =
        (decoded['modules'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    _loadedVersion = decoded['version'] as String?;

    if (outputPath != null) {
      write();
    }

    if (register) {
      current = this;
      ModuleServices.instance.register<NetlistService>(this);
    }
  }

  /// The format version found in the loaded JSON, or `null` if absent.
  String? _loadedVersion;

  /// The format version string from the loaded netlist JSON.
  ///
  /// Returns the `version` field from the JSON if present, otherwise
  /// returns [formatVersion] (assumes current format).
  String get version => _loadedVersion ?? formatVersion;

  /// Checks whether [version] is compatible with the current
  /// [formatVersion].
  ///
  /// Compatible means the major version matches. Returns `true` if
  /// the loaded JSON can be consumed by this version of the service.
  static bool isCompatibleVersion(String version) {
    final current = formatVersion.split('.');
    final other = version.split('.');
    if (other.length < 2 || current.length < 2) {
      return false;
    }
    // Major and minor must match for compatibility.
    return current[0] == other[0] && current[1] == other[1];
  }

  /// Whether the loaded netlist JSON is compatible with the current format.
  bool get isCompatible => isCompatibleVersion(version);

  /// Returns the full netlist hierarchy as a JSON string.
  String get json => _fullJson;

  /// Writes the full netlist [json] to [path], or to [outputPath] when [path]
  /// is omitted.
  @override
  void write([String? path]) {
    final target = path ?? outputPath;
    if (target == null) {
      throw ArgumentError(
        'No output path provided: pass a path to write() or set outputPath.',
      );
    }
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_fullJson);
  }

  /// Returns a JSON-serialisable summary of the netlist synthesis.
  ///
  /// Contains the netlist format version and the list of module definition
  /// names. For the full netlist document, use [json].
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'creator': 'ROHD netlist synthesizer',
        'version': version,
        'modules': moduleNames.toList(),
      };

  /// Returns the netlist JSON for a single module [definitionName].
  ///
  /// The returned JSON is keyed by definition name:
  /// `{"DefinitionName": { ports, cells, netnames }}`.
  /// This matches the format expected by the DevTools schematic viewer
  /// for incremental module fetches.
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
          'version': formatVersion,
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
        'version': formatVersion,
        'rootInstanceName': rootName,
        'modules': slimModules,
      },
    });
  }
}

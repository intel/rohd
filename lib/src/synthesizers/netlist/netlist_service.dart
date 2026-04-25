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
      throw Exception(
          'Module must be built before creating NetlistService. '
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
}

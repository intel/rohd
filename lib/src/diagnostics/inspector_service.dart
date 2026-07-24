// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// inspector_service.dart
// The service that handle interaction between ROHD and Devtools Extension.
//
// 2024 January 23
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

extension _LogicDevToolUtils on Logic {
  /// Converts the current object instance into a JSON string.
  ///
  /// This function uses Dart's built-in `json.encode()` method to convert
  /// the object's properties into a JSON string. The output string will
  /// contain keys such as `name`, `width`, and `value`.
  Map<String, dynamic> toMap() => {
        'name': name,
        'width': width,
        'value': value.toString(),
      };
}

extension _ModuleDevToolUtils on Module {
  /// Convert the [Module] object and its sub-modules into a JSON
  /// representation.
  ///
  /// Returns a JSON map representing the [Module] and its properties.
  ///
  /// If [skipCustomModules] is set to `true` (default), sub-modules that are
  /// instances of [SystemVerilog] will be excluded from the JSON schema.
  Map<String, dynamic> toJson({bool skipCustomModules = true}) {
    final json = {
      'name': name,
      'inputs': inputs.map((key, value) => MapEntry(key, value.toMap())),
      'outputs': outputs.map((key, value) => MapEntry(key, value.toMap())),
    };

    // ignore: deprecated_member_use_from_same_package
    final isCustomModule = this is CustomSystemVerilog || this is SystemVerilog;

    if (!isCustomModule || !skipCustomModules) {
      json['subModules'] = subModules
          .where((module) =>
              // ignore: deprecated_member_use_from_same_package
              !((module is CustomSystemVerilog || module is SystemVerilog) &&
                  skipCustomModules))
          .map((module) => module.toJson(skipCustomModules: skipCustomModules))
          .toList();
    }

    return json;
  }

  /// Generates a JSON schema representing a tree structure of the [Module]
  /// object and its sub-modules.
  ///
  /// The [module] parameter is the root [Module] object for which the JSON
  /// schema is generated.
  ///
  /// By default, sub-modules that are instances of [SystemVerilog] will be
  /// excluded from the schema. Pass [skipCustomModules] as `false` to include
  /// them in the schema.
  ///
  /// Returns a JSON string representing the schema of the [Module] object and
  /// its sub-modules.
  String buildModuleTreeJsonSchema(Module module,
          {bool skipCustomModules = true}) =>
      jsonEncode(toJson(skipCustomModules: skipCustomModules));
}

/// `ModuleTree` implements the Singleton design pattern
/// to ensure there is only one instance of it during runtime.
///
/// This class preserves the legacy DevTools inspector entry point for the
/// built module hierarchy.
class ModuleTree {
  /// Private constructor used to initialize the Singleton instance.
  ModuleTree._();

  /// Singleton instance of `ModuleTree`.
  ///
  /// Always returns the same instance of `ModuleTree`.
  static ModuleTree get instance => _instance;
  static final _instance = ModuleTree._();

  Module? _rootModule;

  /// The root [Module] registered for hierarchy inspection.
  @internal
  Module? get rootModule => _rootModule;

  /// Sets the root [Module] used to produce downstream hierarchy JSON.
  ///
  /// This is kept as an internal setter instead of a writable field so callers
  /// make the bridge explicit: [ModuleServices] is the public service registry,
  /// while [ModuleTree] owns the legacy DevTools hierarchy JSON surface
  /// consumed by downstream hierarchy adapters.
  @internal
  set rootModule(Module? module) {
    _rootModule = module;
  }

  /// Returns the `hierarchyString` as JSON.
  ///
  /// This getter allows access to the `_hierarchyString` string.
  ///
  /// Returns: string representing hierarchical structure of modules in JSON
  /// format.
  String get hierarchyJSON {
    final rootModule = _rootModule;
    return rootModule?.buildModuleTreeJsonSchema(rootModule) ??
        json.encode({
          'status': 'fail',
          'reason': 'module not yet build',
        });
  }
}

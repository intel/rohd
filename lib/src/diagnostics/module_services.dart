// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_services.dart
// Slim, type-keyed registry of module-scoped services for DevTools and other
// inspection tools.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/diagnostics/inspector_service.dart';

/// A slim, type-keyed registry of [ModuleService]s.
class ModuleServices {
  ModuleServices._();

  /// The singleton instance.
  static final ModuleServices instance = ModuleServices._();

  Module? _rootModule;

  /// The most recently built top-level [Module].
  Module? get rootModule => _rootModule;

  set rootModule(Module? value) {
    _rootModule = value;
    ModuleTree.rootModuleInstance = value;
  }

  /// Returns the module hierarchy as a JSON string.
  String get hierarchyJSON => ModuleTree.instance.hierarchyJSON;

  final Map<Type, ModuleService> _services = <Type, ModuleService>{};

  /// Registers [service] under the type argument [T].
  void register<T extends ModuleService>(T service) {
    _services[T] = service;
  }

  /// Returns the registered service of type [T], or `null` if none.
  T? lookup<T extends ModuleService>() => _services[T] as T?;

  /// Removes the registered service of type [T], if any.
  void unregister<T extends ModuleService>() {
    _services.remove(T);
  }

  /// Resets all services. Intended for test teardown.
  void reset() {
    rootModule = null;
    _services.clear();
  }
}

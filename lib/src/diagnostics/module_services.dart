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
///
/// Services register themselves here on construction (keyed by their concrete
/// type) and are retrieved with [lookup].  The registry intentionally exposes
/// no per-format accessors: each service owns its own JSON and output methods,
/// reached through [lookup] or the service's own static `current` accessor.
///
/// The registry references no specific service type, so it is identical across
/// all feature branches that contribute services.
///
/// **Auto-registered:**
///  - [rootModule] / [hierarchyJSON] — set by [Module.build].
class ModuleServices {
  ModuleServices._();

  /// The singleton instance.
  static final ModuleServices instance = ModuleServices._();

  // ─── Hierarchy (auto-registered by Module.build) ──────────────

  /// The most recently built top-level [Module].
  ///
  /// Set automatically at the end of [Module.build].
  Module? rootModule;

  /// Returns the module hierarchy as a JSON string.
  ///
  /// DevTools evaluates this via `EvalOnDartLibrary` to display the module
  /// hierarchy.  Richer design views (e.g. a slim netlist) are composed by the
  /// DevTools client from the relevant registered service.
  String get hierarchyJSON {
    ModuleTree.rootModuleInstance = rootModule;
    return ModuleTree.instance.hierarchyJSON;
  }

  // ─── Type-keyed service registry ──────────────────────────────

  final Map<Type, ModuleService> _services = <Type, ModuleService>{};

  /// Registers [service] under the type argument [T].
  ///
  /// Replaces any previously registered service of the same type.
  void register<T extends ModuleService>(T service) {
    _services[T] = service;
  }

  /// Returns the registered service of type [T], or `null` if none.
  T? lookup<T extends ModuleService>() => _services[T] as T?;

  /// Removes the registered service of type [T], if any.
  void unregister<T extends ModuleService>() {
    _services.remove(T);
  }

  /// Resets all services.  Intended for test teardown.
  void reset() {
    rootModule = null;
    _services.clear();
  }
}

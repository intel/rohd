import 'dart:convert';
import 'dart:developer';
import 'package:rohd/rohd.dart';

/// A class to register extension
class InspectorService {
  /// register module_tree
  InspectorService() {
    registerExtension('ext.rohd.module_tree', (method, parameters) async {
      final a = {
        'name': 'rohd',
        'num': 1,
        'nested': {
          'a': 'n_a',
          '1': 1,
        }
      };

      final jsonVal = json.encode(a);

      return ServiceExtensionResponse.result(jsonVal);
    });
  }
}

/// A class that register module tree (make it singleton).
class ModuleTree {
  static bool _initialized = false;

  ModuleTree._() {
    _initialized = true;
    // ModuleTree.rootModule = null;
  }

  ///
  static ModuleTree get instance => _instance;
  static final _instance = ModuleTree._();

  /// Top level Module
  static Module? rootModule;
  Module? get instanceRootModule => ModuleTree.rootModule;

  /// A function to register tree and stuff.
  static void buildTree() {
    registerExtension('ext.rohd.module_tree', (method, parameters) async {
      final a = {
        'name': 'rohd',
        'num': 1,
        'nested': {
          'a': 'n_a',
          '1': 1,
        }
      };

      final jsonVal = json.encode(a);

      return ServiceExtensionResponse.result(jsonVal);
    });
  }
}

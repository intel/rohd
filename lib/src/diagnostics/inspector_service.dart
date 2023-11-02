import 'dart:convert';
import 'dart:developer';
import 'package:rohd/rohd.dart';

/// A class to register extension
class InspectorService {
  /// register module_tree
  InspectorService() {
    registerExtension('ext.module_tree', (method, parameters) async {
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
  /// Top level Module
  static Module? rootModule;

  /// A function to register tree and stuff.
  static void buildTree() {
    // registerExtension('ext.module_tree', (method, parameters) async {
    //   final rootNode = rootModule.toString();
    //   final jsonVal = json.encode(rootNode);

    //   return ServiceExtensionResponse.result(jsonVal);
    // });

    registerExtension('ext.module_tree', (method, parameters) async {
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

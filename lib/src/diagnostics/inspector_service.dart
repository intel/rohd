import 'dart:convert';
import 'dart:developer';
import 'dart:io';

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

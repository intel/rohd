import 'dart:convert';
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
  /// instances of [CustomSystemVerilog] will be excluded from the JSON schema.
  Map<String, dynamic> toJson({bool skipCustomModules = true}) {
    final json = {
      'name': name,
      // ignore: invalid_use_of_protected_member
      'inputs': inputs.map((key, value) => MapEntry(key, value.toMap())),
      'outputs': outputs.map((key, value) => MapEntry(key, value.toMap())),
    };

    final isCustomModule = this is CustomSystemVerilog;

    if (!isCustomModule || !skipCustomModules) {
      json['subModules'] = subModules
          .where(
              (module) => !(module is CustomSystemVerilog && skipCustomModules))
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
  /// By default, sub-modules that are instances of [CustomSystemVerilog] will
  /// be excluded from the schema.
  /// Pass [skipCustomModules] as `false` to include them in the schema.
  ///
  /// Returns a JSON string representing the schema of the [Module] object
  /// and its sub-modules.
  String buildModuleTreeJsonSchema(Module module,
          {bool skipCustomModules = true}) =>
      jsonEncode(toJson(skipCustomModules: skipCustomModules));
}

/// `ModuleTree` implements the Singleton design pattern
/// to ensure there is only one instance of it during runtime.
///
/// This class is used to maintain a tree-like structure
/// for managing modules in an application.
class ModuleTree {
  /// Private constructor used to initialize the Singleton instance.
  ModuleTree._();

  /// Singleton instance of `ModuleTree`.
  ///
  /// Always returns the same instance of `ModuleTree`.
  static ModuleTree get instance => _instance;
  static final _instance = ModuleTree._();

  /// Stores the root Module instance.
  static Module? rootModuleInstance;

  /// Returns the `hierarchyString` as JSON.
  ///
  /// This getter allows access to the `_hierarchyString` string.
  ///
  /// Returns: string representing hierarchical structure of modules in JSON
  /// format.
  String get hierarchyJSON =>
      rootModuleInstance?.buildModuleTreeJsonSchema(rootModuleInstance!) ?? '';
}

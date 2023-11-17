import 'package:rohd/rohd.dart';

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

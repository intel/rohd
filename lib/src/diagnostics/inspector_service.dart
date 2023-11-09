import 'dart:convert';
import 'dart:developer';
import 'package:rohd/rohd.dart';

abstract class Node {}

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
  // static Module? rootModule;
  // Module? get instanceRootModule => ModuleTree.rootModule;

  static String hierarchyString = '';
  String get hierarchyJSON => hierarchyString;
}

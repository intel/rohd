// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_sub_module_instantiation.dart
// Definitions for a submodule instantiations.
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents an instantiation of a module within another module.
class SynthSubModuleInstantiation {
  /// The module represented.
  final Module module;

  /// The name of this instance.
  String? _name;

  /// Must call [pickName] before this is accessible.
  String get name => _name!;

  /// Selects a name for this module instance. Must be called exactly once.
  ///
  /// Names are allocated from [parentModule]'s `Namer`'s shared namespace
  /// via `Namer.allocateInstanceName`.
  void pickName(Module parentModule) {
    assert(_name == null, 'Should only pick a name once.');

    _name = parentModule.namer.allocateInstanceName(
      module.uniqueInstanceName,
      reserved: module.reserveName,
    );
  }

  /// A mapping of input port name to [SynthLogic].
  late final Map<String, SynthLogic> inputMapping =
      UnmodifiableMapView(_inputMapping);
  final Map<String, SynthLogic> _inputMapping = {};

  /// Adds an input mapping from [name] to [synthLogic].
  void setInputMapping(String name, SynthLogic synthLogic,
      {bool replace = false}) {
    assert(module.inputs.containsKey(name),
        'Input $name not found in module ${module.name}.');
    assert(
        (replace && _inputMapping.containsKey(name)) ||
            !_inputMapping.containsKey(name),
        'A mapping already exists to this input: $name.');

    _inputMapping[name] = synthLogic;
  }

  /// A mapping of output port name to [SynthLogic].
  late final Map<String, SynthLogic> outputMapping =
      UnmodifiableMapView(_outputMapping);
  final Map<String, SynthLogic> _outputMapping = {};

  /// Adds an output mapping from [name] to [synthLogic].
  void setOutputMapping(String name, SynthLogic synthLogic,
      {bool replace = false}) {
    assert(module.outputs.containsKey(name),
        'Output $name not found in module ${module.name}.');
    assert(
        (replace && _outputMapping.containsKey(name)) ||
            !_outputMapping.containsKey(name),
        'A mapping already exists to this output: $name.');

    _outputMapping[name] = synthLogic;
  }

  /// A mapping of output port name to [SynthLogic].
  late final Map<String, SynthLogic> inOutMapping =
      UnmodifiableMapView(_inOutMapping);
  final Map<String, SynthLogic> _inOutMapping = {};

  /// Adds an inOut mapping from [name] to [synthLogic].
  void setInOutMapping(String name, SynthLogic synthLogic,
      {bool replace = false}) {
    assert(module.inOuts.containsKey(name),
        'InOut $name not found in module ${module.name}.');
    assert(
        (replace && _inOutMapping.containsKey(name)) ||
            !_inOutMapping.containsKey(name),
        'A mapping already exists to this output: $name.');

    _inOutMapping[name] = synthLogic;
  }

  /// Indicates whether this module should be declared.
  bool get needsInstantiation => _needsInstantiation;
  bool _needsInstantiation = true;

  /// Removes the need for this module to be declared (via
  /// [needsInstantiation]).
  void clearInstantiation() {
    _needsInstantiation = false;
  }

  /// Creates an instantiation for [module].
  SynthSubModuleInstantiation(this.module);

  @override
  String toString() =>
      "_SynthSubModuleInstantiation ${_name == null ? 'null' : '"$name"'}, "
      "module name:'${module.name}'";
}

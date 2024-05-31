// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tristate.dart
// A tri-state buffer.
//
// 2024 May 30
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A tri-state buffer: can drive 0, 1, or leave the output floating.
class TriStateBuffer extends Module with SystemVerilog {
  /// Name for the control signal of this mux.
  late final String _enableName;

  /// Name for the input port of this module.
  late final String _inName;

  /// Name for the output port of this module.
  late final String _outName;

  /// The input to this gate.
  late final Logic _in = input(_inName);

  /// The control signal for this [TriStateBuffer].
  late final Logic _enable = input(_enableName);

  /// The output of this gate (width is always 1).
  late final LogicNet out;

  /// An internal signal for the modelling logic to drive.
  final Logic _outDriver;

  /// Creates a tri-state buffer which drives [out] with [in_] if [enable] is
  /// high, otherwise leaves it floating `z`.
  TriStateBuffer(Logic in_, {required Logic enable, super.name = 'tristate'})
      : _outDriver = Logic(name: 'outDriver', width: in_.width) {
    _inName = Naming.unpreferredName(in_.name);
    _outName = Naming.unpreferredName('${name}_${in_.name}');
    _enableName = Naming.unpreferredName('enable_${enable.name}');

    addInput(_inName, in_, width: in_.width);
    addInput(_enableName, enable);

    out = LogicNet(width: in_.width);
    addInOut(_outName, out, width: in_.width) <= _outDriver;

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute();

    _in.glitch.listen((args) {
      _execute();
    });
    _enable.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of the tristate buffer.
  void _execute() {
    if (!_enable.value.isValid) {
      _outDriver.put(LogicValue.x);
    } else if (_enable.value == LogicValue.one) {
      _outDriver.put(_in.value);
    } else {
      _outDriver.put(LogicValue.z);
    }
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    assert(ports.length == 3, 'Tristate buffer should have 2 inputs, 1 inout.');

    final in_ = ports[_inName]!;
    final enable = ports[_enableName]!;
    final out = ports[_outName];
    return 'assign $out = $enable ? $in_ : ${LogicValue.filled(_in.width, LogicValue.z)}; // tristate';
  }
}

// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wire_net.dart
// Definition for `_WireNet`.
//
// 2024 May 30
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

class _WireNet extends _Wire {
  final Set<Logic> _drivers = {};

  _WireNet({required super.width});

  void _evaluateNewValue({required String signalName}) {
    var newValue = LogicValue.filled(width, LogicValue.z);
    for (final driver in _drivers) {
      newValue = newValue.triState(driver.value);
    }
    put(newValue, signalName: signalName);
  }

  @override
  void _adopt(_Wire other) {
    assert(other is _WireNet, 'Only should be adopting other `_WireNet`s');
    other as _WireNet;

    super._adopt(other);

    other._drivers
      ..forEach(_addDriver)
      ..clear();
  }

  void _addDriver(Logic driver) {
    if (_drivers.add(driver)) {
      driver.glitch.listen((args) {
        _evaluateNewValue(signalName: driver.name);
      });
    }
  }
}

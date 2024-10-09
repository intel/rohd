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

  late final List<_WireNetBlasted> _parents = []; //TODO review

  _WireNet({required super.width});

  void _addParent(_WireNetBlasted parent) {
    _parents.add(parent);
  }

  void _evaluateNewValue({required String signalName}) {
    var newValue = LogicValue.filled(width, LogicValue.z);
    for (final driver in _drivers) {
      newValue = newValue.triState(driver.value);
    }
    put(newValue, signalName: signalName);
  }

  @override
  _Wire _adopt(_Wire other) {
    assert(other is _WireNet, 'Only should be adopting other `_WireNet`s');
    assert(other.width == width, 'Width mismatch');
    other as _WireNet;

    if (other is _WireNetBlasted) {
      return other._adopt(this);
    }

    super._adopt(other);

    other._drivers
      ..forEach(_addDriver)
      ..clear();

    other._parents
      ..forEach((p) => p._replaceWire(other, this))
      ..clear();

    return this;
  }

  void _addDriver(Logic driver) {
    if (_drivers.add(driver)) {
      //TODO: eliminiate glitch listeners after adoption!? (in all wires)
      driver.glitch.listen((args) {
        _evaluateNewValue(signalName: driver.name);
      });
    }
  }

  _WireNetBlasted blast() => _WireNetBlasted.fromWireNet(this);
}

class _WireNetBlasted extends _Wire implements _WireNet {
  final List<_WireNet> _wires;

  // _WireNetBlasted({required super.width})
  //     : _wires = List<_WireNet>.generate(width, (i) => _WireNet(width: 1));

  _WireNetBlasted.fromWireNet(_WireNet wire)
      : _wires = List<_WireNet>.generate(wire.width, (i) => _WireNet(width: 1)),
        super(width: wire.width) {
    for (final w in _wires) {
      w._addParent(this);
    }
    super._adopt(wire);
    wire._drivers
      ..forEach(_addDriver)
      ..clear();
  }

  void _replaceWire(_WireNet oldWire, _WireNet newWire) {
    _wires[_wires.indexOf(oldWire)] = newWire;
  }

  @override
  _Wire _adopt(_Wire other) {
    assert(other is _WireNet || other is _WireNetBlasted,
        'Only should be adopting other `_WireNet`s');
    assert(other.width == width, 'Width mismatch');

    other as _WireNet;

    if (other is! _WireNetBlasted) {
      // ignore: parameter_assignments
      other = other.blast();
    }

    super._adopt(other);

    for (var i = 0; i < width; i++) {
      _wires[i]._adopt(other._wires[i]);
    }

    return this;
  }

  void _addDriver(Logic driver) {
    for (var i = 0; i < width; i++) {
      _wires[i]._addDriver(driver[i]);
    }
  }

  @override
  LogicValue get value => LogicValue.ofIterable(_wires.map((e) => e.value));

  @override
  set _currentValue(LogicValue newValue) =>
      throw Exception('Not supported'); //TODO

  @override
  void _updateValue(LogicValue newValue) {
    for (var i = 0; i < width; i++) {
      _wires[i]._updateValue(newValue[i]);
    }
  }

  void _adoptSubset(_WireNetBlasted other, {required int start}) {
    for (var i = 0; i < other.width; i++) {
      _wires[start + i]._adopt(other._wires[i]);
    }
  }

  @override
  _WireNetBlasted blast() => this;

  @override
  void _evaluateNewValue({required String signalName}) {
    for (final wire in _wires) {
      wire._evaluateNewValue(signalName: signalName);
    }
  }

  @override
  // TODO
  Set<Logic> get _drivers => throw UnimplementedError();

  @override
  void _addParent(_WireNetBlasted parent) {
    //TODO
    throw UnimplementedError();
  }

  @override
  // TODO: implement _parents
  List<_WireNetBlasted> get _parents => throw UnimplementedError();
}

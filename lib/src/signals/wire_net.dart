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

  //TODO: is there a way to merge/reduce the number of parents to track?
  late final Set<_WireNetBlasted> _parents = {}; //TODO review

  _WireNet({required super.width});

  void _addParent(_WireNetBlasted parent) {
    assert(width == 1, 'Only should be adding parents to blasted wires');
    _parents.add(parent);
  }

  void _removeParent(_WireNetBlasted parent) {
    assert(width == 1, 'Only should be removing parents from blasted wires');

    final removed = _parents.remove(parent);

    assert(removed, 'Parent not found to remove');
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

    if (other == this) {
      // nothing to do if this is the same wire already!
      return this;
    }

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

  _WireNetBlasted.fromWireNet(_WireNet wire)
      : _wires = List<_WireNet>.generate(wire.width, (i) => _WireNet(width: 1)),
        assert(
            wire is! _WireNetBlasted, 'Should not be blasting a blasted wire'),
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
    final index = _wires.indexOf(oldWire);

    if (index >= 0) {
      // assert(index != -1, 'Wire should be there to replace.');
      _wires[index] = newWire.._addParent(this);

      // old wire parents need to be notified!! //TODO THIS IS THE PIECE THAT WAS MISSING
      for (final parent in oldWire._parents) {
        parent._replaceWire(oldWire, newWire);
      }
    }
  }

  @override
  _Wire _adopt(_Wire other) {
    assert(other is _WireNet, 'Only should be adopting other `_WireNet`s');
    assert(other.width == width, 'Width mismatch');

    other as _WireNet;

    if (other is! _WireNetBlasted) {
      // ignore: parameter_assignments
      other = other.blast();
    }

    super._adopt(other);

    for (var i = 0; i < width; i++) {
      _wires[i] = _wires[i]._adopt(other._wires[i]) as _WireNet;
      //TODO: this is not safe because multiple wires could point to it for multiple reasons, is there a safe way?
      // .._removeParent(other);

      assert(_wires[i]._parents.contains(this), 'Parent not added');
    }

    return this;
  }

  @override
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
      _wires[start + i] = _wires[start + i]._adopt(other._wires[i]) as _WireNet;
      assert(_wires[start + i]._parents.contains(this), 'Parent not added');
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
  Set<_WireNetBlasted> get _parents => throw UnimplementedError();

  @override
  void _removeParent(_WireNetBlasted parent) {
    // TODO
    throw UnimplementedError();
  }
}

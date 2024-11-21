// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wire_net.dart
// Definition for `_WireNet`.
//
// 2024 May 30
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Represents a driver of a [_WireNet], optionally with an index.
@immutable
class _WireNetDriver {
  /// The signal doing the driving.
  final Logic signal;

  /// If non-null, the index of [signal] that is driving the same index of the
  /// receiver (always the same).
  final int? index;

  /// Indicates if the full width is driven or only one index of it.
  bool get isFullWidth => index == null;

  /// Creates a tracker for a driver of a [_WireNet].
  const _WireNetDriver(this.signal, [this.index]);

  @override
  String toString() => '$signal [$index]';

  @override
  bool operator ==(Object other) =>
      other is _WireNetDriver && signal == other.signal && index == other.index;

  @override
  int get hashCode => signal.hashCode ^ index.hashCode;
}

class _WireNet extends _Wire {
  final Set<_WireNetDriver> _drivers = {};

  //TODO: is there a way to merge/reduce the number of parents to track?
  late final Set<_WireNetBlasted> _parents = {}; //TODO review

  _WireNet({required super.width});

  void _addParent(_WireNetBlasted parent) {
    assert(width == 1, 'Only should be adding parents to blasted wires');
    _parents.add(parent);
  }

  void _evaluateNewValue({required String signalName}) {
    var newValue = LogicValue.filled(width, LogicValue.z);
    for (final driver in _drivers) {
      final valueToTristate = driver.isFullWidth
          ? driver.signal.value
          : driver.signal.value[driver.index!];

      newValue = newValue.triState(valueToTristate);
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

    //TODO
    assert(!(this is _WireNetBlasted && other is _WireNetBlasted),
        'not sure if this is handled correctly?');

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

  void _addDriver(_WireNetDriver driver) {
    if (_drivers.add(driver)) {
      //TODO: eliminiate glitch listeners after adoption!? (in all wires)
      // maybe already taken care of via adoption?
      driver.signal.glitch.listen((args) {
        _evaluateNewValue(signalName: driver.signal.name);
      });
    }
  }

  /// Converts this to a [_WireNetBlasted].
  _WireNetBlasted toBlasted() => _WireNetBlasted.fromWireNet(this);

  @override
  String toString() => '${super.toString()} (net)';
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

    // need to set up glitch listener for whole wire together
    for (var i = 0; i < width; i++) {
      _wires[i].glitch.listen((wireValueChange) {
        //TODO: test that glitch properly updates!
        //TODO: test that reassigning properly migrates glitch listeners!
        //TODO: is there a way to do this more efficiently?
        _glitchController.add(LogicValueChanged(
            value, value.withSet(i, wireValueChange.previousValue)));
      });
    }
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

    if (other == this) {
      // nothing to do if this is the same wire already!
      return this;
    }

    other as _WireNet;

    if (other is! _WireNetBlasted) {
      // ignore: parameter_assignments
      other = other.toBlasted();
    }

    super._adopt(other);

    for (var i = 0; i < width; i++) {
      _wires[i] = _wires[i]._adopt(other._wires[i]) as _WireNet;

      assert(_wires[i]._parents.contains(this), 'Parent not added');
    }

    return this;
  }

  @override
  void _addDriver(_WireNetDriver driver) {
    for (var i = 0; i < width; i++) {
      _wires[i]._addDriver(_WireNetDriver(driver.signal, i));
    }
  }

  @override
  LogicValue get value => LogicValue.ofIterable(_wires.map((e) => e.value));

  @override
  set _currentValue(LogicValue newValue) =>
      throw Exception('Not supported'); //TODO

  //TODO: test puts directly on the wire?
  @override
  void _updateValue(LogicValue newValue, {required String signalName}) {
    for (var i = 0; i < width; i++) {
      _wires[i]._updateValue(newValue[i], signalName: signalName);
    }
    // _evaluateNewValue(signalName: signalName); //TODO: is this needed? no, inf loop
  }

  void _adoptSubset(_WireNetBlasted other, {required int start}) {
    for (var i = 0; i < other.width; i++) {
      _wires[start + i] = _wires[start + i]._adopt(other._wires[i]) as _WireNet;
      assert(_wires[start + i]._parents.contains(this), 'Parent not added');
    }
  }

  @override
  _WireNetBlasted toBlasted() => this;

  @override
  void _evaluateNewValue({required String signalName}) {
    for (final wire in _wires) {
      wire._evaluateNewValue(signalName: signalName);
    }
  }

  @override
  Set<_WireNetDriver> get _drivers => throw UnimplementedError();

  @override
  void _addParent(_WireNetBlasted parent) => throw UnimplementedError();

  @override
  Set<_WireNetBlasted> get _parents => throw UnimplementedError();

  @override
  String toString() => '${super.toString()} (net blasted)';
}

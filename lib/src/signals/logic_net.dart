//TODO:header

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

class LogicNet extends Logic {
  @override
  Logic? get srcConnection => null;

  @override
  bool get isNet => true;

  LogicNet({super.name, super.width, super.naming})
      : super._(wire: _WireNet(width: width));

  factory LogicNet.port(String name, [int width = 1]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicNet(
      name: name,
      width: width,

      // make port names mergeable so we don't duplicate the ports
      // when calling connectIO
      naming: Naming.mergeable,
    );
  }

  @override
  void _connect(Logic other) {
    // if they are already connected, don't connect again!
    if (_srcConnections.contains(other)) {
      return;
    }

    if (other is LogicNet) {
      _updateWire(other._wire);
    } else {
      (_wire as _WireNet)._addDriver(other);
    }

    (_wire as _WireNet)._evaluateNewValue(signalName: name);

    if (other != this) {
      _srcConnections.add(other);
    }
  }

  @override
  String toString() => '${super.toString()}, [Net]';
}

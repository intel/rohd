part of 'signals.dart';

//TODO: this must be represented as `wire` in SV
//TODO: in verilog, must use continuous assignment to this, not always block (no procedural)
//TODO: Z checking should be per-bit, not per bus! (do this in LogicValue)

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
  /// TODO: doc: UndirectionalLogic can have any number of srcConnections
  @override
  Logic? get srcConnection => null;

  late final List<Logic> srcConnections = UnmodifiableListView(_srcConnections);
  List<Logic> _srcConnections = [];

  LogicNet({super.name, super.width, super.naming})
      : super._(wire: _WireNet(width: width)) {}

  //TODO: NO, this needs to be separately tracked?
  // Set<Logic> get _srcConnections => (_wire as _WireNet)._drivers;

  @override
  void _connect(Logic other) {
    //TODO: cannot merge wires with non-Nets!
    //TODO: should there really be a different type? or just a setting on Logic?

    if (other is LogicNet) {
      _updateWire(other._wire);
    } else {
      (_wire as _WireNet)._addDriver(other);
    }

    (_wire as _WireNet)._evaluateNewValue(signalName: name);

    _srcConnections.add(other);
  }

  @override
  String toString() => 'LogicNet($width): $name';
}

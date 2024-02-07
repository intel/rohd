part of 'signals.dart';

//TODO: this must be represented as `wire` in SV
//TODO: in verilog, must use continuous assignment to this, not always block (no procedural)
//TODO: Z checking should be per-bit, not per bus! (do this in LogicValue)

class _WireNet extends _Wire {
  final Set<Logic> _srcConnections = {};

  _WireNet({required super.width});

  void _evaluateNewValue({required String signalName}) {
    var newValue = LogicValue.filled(width, LogicValue.z);
    for (final srcConnection in _srcConnections) {
      newValue = newValue.triState(srcConnection.value);
    }
    put(newValue, signalName: signalName);
  }

  @override
  void _adopt(_Wire other) {
    assert(other is _WireNet, 'Only should be adopting other `_WireNet`s');
    other as _WireNet;

    super._adopt(other);

    other._srcConnections
      ..forEach(_addSrcConnection)
      ..clear();
  }

  void _addSrcConnection(Logic srcConnection) {
    _srcConnections.add(srcConnection);
    srcConnection.glitch.listen((args) {
      _evaluateNewValue(signalName: srcConnection.name);
    });
  }
}

class LogicNet extends Logic {
  /// TODO: doc: UndirectionalLogic can have any number of srcConnections
  @override
  Logic? get srcConnection => null;

  LogicNet({super.name, super.width, super.naming})
      : super._(wire: _WireNet(width: width)) {}

  Set<Logic> get _srcConnections => (_wire as _WireNet)._srcConnections;

  @override
  void _connect(Logic other) {
    _updateWire(other._wire);

    //TODO: cannot merge wires with non-Nets!
    //TODO: should there really be a different type? or just a setting on Logic?

    (_wire as _WireNet)
      .._addSrcConnection(other)
      .._evaluateNewValue(signalName: name);
  }
}

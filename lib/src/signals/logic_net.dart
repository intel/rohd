part of 'signals.dart';

//TODO: this must be represented as `wire` in SV
//TODO: in verilog, must use continuous assignment to this, not always block (no procedural)
//TODO: Z checking should be per-bit, not per bus! (do this in LogicValue)

//TODO: DO NOT EXPOSE - removable!
// TODO: rename
class NetConnect extends Module with SystemVerilog {
  static const String _definitionName = 'net_connect';

  final int width;

  late final String _aName = Naming.unpreferredName('a');
  late final String _bName = Naming.unpreferredName('b');

  NetConnect(LogicNet a, LogicNet b)
      : assert(a.width == b.width, 'Widths must be equal.'),
        width = a.width,
        super(
          definitionName: _definitionName,
          name: _definitionName,
        ) {
    a = addInOut(_aName, a, width: width);
    b = addInOut(_bName, b, width: width);
  }

  //TODO: override unique instance name?

  @override
  String instantiationVerilog(
      String instanceType, String instanceName, Map<String, String> ports) {
    assert(instanceType == _definitionName,
        'Instance type selected should match the definition name.');
    return '$instanceType'
        ' #(.WIDTH($width))'
        ' $instanceName'
        ' (${ports[_aName]}, ${ports[_bName]});';
  }

  @override
  String? definitionVerilog(String definitionType) => '''
// A special module for connecting two nets bidirectionally
module $definitionType #(parameter WIDTH=1) (w, w); 
inout wire[WIDTH-1:0] w;
endmodule''';
}

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

  //TODO
  @override
  final bool isNet = true;

  late final Iterable<Logic> srcConnections =
      UnmodifiableListView(_srcConnections);
  Set<Logic> _srcConnections = {};

  //TODO: should we just have a generic "connections"?

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

  //TODO: NO, this needs to be separately tracked?
  // Set<Logic> get _srcConnections => (_wire as _WireNet)._drivers;

  @override
  void _connect(Logic other) {
    //TODO: cannot merge wires with non-Nets!
    //TODO: should there really be a different type? or just a setting on Logic?

    if (other is LogicNet) {
      _updateWire(other._wire);

      if (parentModule is! NetConnect) {
        //TODO: hacky?
        NetConnect(this, other);
      }
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

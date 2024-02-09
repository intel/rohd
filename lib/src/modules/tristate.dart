import 'package:rohd/rohd.dart';

class TriStateBuffer extends Module with CustomSystemVerilog {
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
  //TODO
  // late final Logic out = output(_outName);
  late final Logic out = inOut(_outName);

  //TODO
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

    //TODO
    // addOutput(_outName, width: in_.width);
    addInOut(_outName, LogicNet(width: in_.width)..gets(_outDriver),
        width: in_.width);

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

  // @override
  // String inlineVerilog(Map<String, String> inputs) {
  //   assert(inputs.length == 2, 'Tristate buffer should have 2 inputs.');
  //   final in_ = inputs[_inName]!;
  //   final enable = inputs[_enableName]!;
  //   return '$enable ? $in_ : ${LogicValue.filled(_in.width, LogicValue.z)}';
  // }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    //TODO
    throw UnimplementedError();
  }

  @override
  String instantiationVerilogWithInOuts(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      Map<String, String> inOuts) {
    assert(inputs.length == 2, 'Tristate buffer should have 2 inputs.');
    assert(outputs.isEmpty);
    assert(inOuts.length == 1);

    final in_ = inputs[_inName]!;
    final enable = inputs[_enableName]!;
    final out = inOuts[_outName];
    return 'assign $out = $enable ? $in_ : ${LogicValue.filled(_in.width, LogicValue.z)}; // tristate';
  }
}

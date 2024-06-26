import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

const _bParam = 7;

abstract class ModWithParamPassthrough extends Module with SystemVerilog {
  ModWithParamPassthrough(this.definitionParameters,
      {required this.instantiationParameters,
      super.definitionName,
      super.name});

  @override
  final List<SystemVerilogParameter> definitionParameters;

  final Map<String, String> instantiationParameters;

  @override
  String? definitionVerilog(String definitionType) => null;

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) =>
      SystemVerilogSynthesizer.instantiationVerilogFor(
        module: this,
        instanceType: definitionName,
        instanceName: instanceName,
        ports: ports,
        parameters: instantiationParameters,
        forceStandardInstantiation: true,
      );
}

class Top extends ModWithParamPassthrough {
  Logic get b => output('b');
  Top(Logic a, {super.instantiationParameters = const {}, super.name = 'top'})
      : super([
          const SystemVerilogParameter('A', type: 'int', defaultValue: '3'),
          const SystemVerilogParameter('B',
              type: 'int', defaultValue: '$_bParam'),
          const SystemVerilogParameter('C',
              type: 'bit[3:0]', defaultValue: '2'),
        ]) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);
    b <=
        Mid(
          a,
          instantiationParameters: Map.fromEntries(
              definitionParameters.map((e) => MapEntry(e.name, e.name))),
        ).b;
  }
}

class Mid extends ModWithParamPassthrough {
  Logic get b => output('b');
  Mid(Logic a, {super.instantiationParameters = const {}, super.name = 'mid'})
      : super([
          const SystemVerilogParameter('A', type: 'int', defaultValue: '3'),
          const SystemVerilogParameter('B', type: 'int', defaultValue: '0'),
          const SystemVerilogParameter('C',
              type: 'bit[3:0]', defaultValue: '0'),
          const SystemVerilogParameter('D',
              type: 'logic', defaultValue: "1'b0"),
        ]) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);
    b <=
        LeafNodeExternal(
          a,
          instantiationParameters: Map.fromEntries(
              definitionParameters.map((e) => MapEntry(e.name, e.name))),
        ).b;
  }
}

class LeafNodeExternal extends ModWithParamPassthrough {
  Logic get b => output('b');
  LeafNodeExternal(Logic a,
      {super.definitionName = 'leaf_node',
      super.instantiationParameters = const {},
      super.name = 'leaf'})
      : super([
          const SystemVerilogParameter('A', type: 'int', defaultValue: '0'),
          const SystemVerilogParameter('B', type: 'int', defaultValue: '0'),
          const SystemVerilogParameter('C',
              type: 'bit[3:0]', defaultValue: '0'),
          const SystemVerilogParameter('D', type: 'logic', defaultValue: '0'),
        ]) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);
  }

  // leaf node should not generate any SV, like external
  @override
  String? definitionVerilog(String definitionType) => '';
}

void main() {
  test('passthrough params custom system verilog', () async {
    final mod = Top(Logic(width: 8));
    await mod.build();

    final vectors = [
      Vector({'a': 1}, {'b': 1 + _bParam}),
      Vector({'a': 3}, {'b': 3 + _bParam}),
    ];

    SimCompare.checkIverilogVector(mod, vectors, iverilogExtraArgs: [
      'test/sv_param_passthrough.sv', // include external SV
    ]);
  });
}

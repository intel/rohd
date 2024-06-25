import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

abstract class ModWithParamPassthrough extends Module with SystemVerilog {
  ModWithParamPassthrough(this.definitionParameters, {super.definitionName});

  @override
  final List<SystemVerilogParameter> definitionParameters;

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
        parameters: Map.fromEntries(
            definitionParameters.map((e) => MapEntry(e.name, e.name))),
        forceStandardInstantiation: true,
      );
}

class Top extends ModWithParamPassthrough {
  Top(Logic a)
      : super([
          const SystemVerilogParameter('A', defaultValue: '3'),
          const SystemVerilogParameter('B', type: 'int'),
          const SystemVerilogParameter('C',
              type: 'bit[3:0]', defaultValue: '2'),
        ]) {
    a = addInput('a', a);
  }
}

class Mid extends ModWithParamPassthrough {
  Mid(Logic a)
      : super([
          const SystemVerilogParameter('A', defaultValue: '3'),
          const SystemVerilogParameter('B', type: 'int'),
          const SystemVerilogParameter('C', type: 'bit[3:0]'),
          const SystemVerilogParameter('D',
              type: 'string', defaultValue: '"asdf"'),
        ]) {
    a = addInput('a', a);
  }
}

class LeafNodeExternal extends ModWithParamPassthrough {
  LeafNodeExternal(Logic a, {super.definitionName = 'leaf_node'})
      : super([
          const SystemVerilogParameter('A'),
          const SystemVerilogParameter('B', type: 'int'),
          const SystemVerilogParameter('C', type: 'bit[3:0]'),
          const SystemVerilogParameter('D', type: 'string'),
        ]) {
    a = addInput('a', a);
  }

  // leaf node should not generate any SV, like external
  @override
  String? definitionVerilog(String definitionType) => '';
}

void main() {
  test('passthrough params custom system verilog', () async {
    final mod = Top(Logic());
    await mod.build();
    print(mod.generateSynth());
  });
}

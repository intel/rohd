import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  final bool asNet;

  factory MyStruct({String? name, bool asNet = false}) => MyStruct._(
        (asNet ? LogicNet.new : Logic.new)(
            name: 'ready', naming: Naming.mergeable),
        (asNet ? LogicNet.new : Logic.new)(
            name: 'valid', naming: Naming.mergeable),
        name: name,
        asNet: asNet,
      );

  MyStruct._(this.ready, this.valid,
      {required String? name, required this.asNet})
      : super([ready, valid], name: name ?? 'myStruct');

  @override
  MyStruct clone({String? name}) =>
      MyStruct(name: name ?? this.name, asNet: asNet);
}

class SimpleStructModule extends Module {
  late final MyStruct myOut;

  SimpleStructModule(MyStruct myIn, {super.name = 'simple_struct_mod'}) {
    myIn = (myIn.isNet ? addMatchedInOut : addMatchedInput)('myIn', myIn);

    final internal = myIn.clone(name: 'internal_struct');
    internal.ready <= myIn.valid;
    internal.valid <= myIn.ready;

    if (myIn.isNet) {
      myOut = myIn.clone(name: 'myOutExt');
      addMatchedInOut('myOut', myOut) <= internal;
    } else {
      myOut = addMatchedOutput('myOut', internal)..gets(internal);
    }
  }
}

class SimpleStructModuleContainer extends Module {
  SimpleStructModuleContainer(Logic a1, Logic a2,
      {super.name = 'simple_struct_mod_container', bool asNet = false}) {
    final Logic Function(String, Logic) inMaker = asNet ? addInOut : addInput;
    // ignore: omit_local_variable_types
    final Logic Function(String name) outMaker = asNet
        ? (name) => addInOut(name, LogicNet(name: 'ext$name'))
        : addOutput;

    a1 = inMaker('a1', a1);
    a2 = inMaker('a2', a2);
    final upperStruct = MyStruct(name: 'upper_struct', asNet: asNet);
    upperStruct.ready <= a1;
    upperStruct.valid <= a2;
    final sub = SimpleStructModule(upperStruct);

    outMaker('b1') <= sub.myOut.ready;
    outMaker('b2') <= sub.myOut.valid;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple struct module', () async {
    final mod = SimpleStructModuleContainer(Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, isNot(contains('internal_struct')));

    expect(sv, contains('input logic [1:0] myIn'));
    expect(sv, contains('output logic [1:0] myOut'));

    final vectors = [
      Vector({'a1': 0, 'a2': 1}, {'b1': 1, 'b2': 0}),
      Vector({'a1': 1, 'a2': 0}, {'b1': 0, 'b2': 1}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('simple struct module with nets', () {
    Future<Module> makeMod() async {
      final mod =
          SimpleStructModuleContainer(LogicNet(), LogicNet(), asNet: true);
      await mod.build();

      final sv = mod.generateSynth();

      expect(sv, isNot(contains('internal_struct')));

      expect(sv, contains('inout wire [1:0] myIn'));
      expect(sv, contains('inout wire [1:0] myOut'));

      return mod;
    }

    test('forward', () async {
      final mod = await makeMod();

      final vectors = [
        Vector({'a1': 0, 'a2': 1}, {'b1': 1, 'b2': 0}),
        Vector({'a1': 1, 'a2': 0}, {'b1': 0, 'b2': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('reversed', () async {
      final mod = await makeMod();

      final vectorsReversed = [
        Vector({'b1': 1, 'b2': 0}, {'a1': 0, 'a2': 1}),
        Vector({'b1': 0, 'b2': 1}, {'a1': 1, 'a2': 0}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsReversed);
      SimCompare.checkIverilogVector(mod, vectorsReversed);
    });
  });
}

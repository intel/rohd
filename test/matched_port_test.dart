import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory MyStruct({String? name}) => MyStruct._(
        Logic(name: 'ready', naming: Naming.mergeable),
        Logic(name: 'valid', naming: Naming.mergeable),
        name: name,
      );

  MyStruct._(this.ready, this.valid, {String? name})
      : super([ready, valid], name: name ?? 'myStruct');

  @override
  LogicStructure clone({String? name}) => MyStruct(name: name);
}

class SimpleStructModule extends Module {
  MyStruct get myOut => output('myOut') as MyStruct;

  SimpleStructModule(MyStruct myIn, {super.name = 'simple_struct_mod'}) {
    myIn = addMatchedInput('myIn', myIn);

    final internal = MyStruct(name: 'internal_struct');
    internal.ready <= myIn.valid;
    internal.valid <= myIn.ready;

    addMatchedOutput('myOut', internal) <= internal;
  }
}

class SimpleStructModuleContainer extends Module {
  SimpleStructModuleContainer(Logic a1, Logic a2,
      {super.name = 'simple_struct_mod_container'}) {
    a1 = addInput('a1', a1);
    a2 = addInput('a2', a2);
    final myStruct = MyStruct(name: 'upper_struct');
    myStruct.ready <= a1;
    myStruct.valid <= a2;
    final sub = SimpleStructModule(myStruct);

    addOutput('b1') <= sub.myOut.ready;
    addOutput('b2') <= sub.myOut.valid;
  }
}

void main() {
  test('simple struct module', () async {
    final mod = SimpleStructModuleContainer(Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv, isNot(contains('internal_struct')));

    print(sv);
  });
}

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SsaModAssignsOnly extends Module {
  SsaModAssignsOnly(Logic a) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);
    Combinational.ssa((s) => [
          s(x) < a,
          s(x) < s(x) + 1,
          s(x) < s(x) + s(x),
        ]);
  }
}

class SsaModIf extends Module {
  SsaModIf(Logic a) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);

    Combinational.ssa((s) => [
          s(x) < a + 1,
          If(s(x), then: [
            s(x) < s(x) + 2,
          ], orElse: [
            s(x) < s(x) + 3,
          ]),
          s(x) < s(x) + 1,
        ]);
  }
}

class SsaModCase extends Module {
  SsaModCase(Logic a) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);

    Combinational.ssa((s) => [
          s(x) < a + 1,
          s(x) < s(x) + 1,
          Case(s(x), [
            CaseItem(s(x), [s(x) < s(x) + 4])
          ], defaultItem: [
            s(x) < 3
          ]),
        ]);
  }
}

//TODO: test with multiple ssa things connected to each other that it doesnt get confused!
//TODO: test crazy hierarcical if/else things
//TODO: test where an SSA conditional is generated during generation of another SSA conditional
//TODO: test that uninitialized variable throws exception
//TODO: test when variable is not "initialized"

void main() {
  test('ssa simple assignments only', () async {
    final mod = SsaModAssignsOnly(Logic(width: 8));
    await mod.build();
    // print(mod.generateSynth());
  });

  test('ssa case', () async {
    final mod = SsaModCase(Logic(width: 8));
    await mod.build();
    // print(mod.generateSynth());
  });

  test('ssa if', () async {
    final mod = SsaModIf(Logic(width: 8));
    await mod.build();
    // print(mod.generateSynth());
  });
}

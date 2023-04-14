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

//TODO: test when variable is not "initialized"

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

void main() {
  test('ssa simple assignments only', () async {
    final mod = SsaModAssignsOnly(Logic(width: 8));
    await mod.build();
    print(mod.generateSynth());
  });

  test('ssa case', () async {
    final mod = SsaModCase(Logic(width: 8));
    await mod.build();
    print(mod.generateSynth());
  });
}

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

class SsaModExample extends Module {
  SsaModExample(Logic a) {
    a = addInput('a', a);
    final x = addOutput('x');

    Combinational.ssa((s) => [
          s(x) < 1,
          If(a, then: [
            s(x) < s(x) + 2,
          ], orElse: [
            s(x) < s(x) + 3,
          ]),
          // inject phi
          s(x) < s(x) + 1,
        ]);
  }
}

void main() {
  test('simple assignments only', () async {
    final mod = SsaModAssignsOnly(Logic(width: 8));
    await mod.build();
    print(mod.generateSynth());
  });
}

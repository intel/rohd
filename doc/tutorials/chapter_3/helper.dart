import 'package:rohd/rohd.dart';

class FAResult {
  int sum = 0;
  int cOut = 0;
}

FAResult faTruthTable(int a, int b, int cIn) {
  final res = FAResult();
  if (a + b + cIn == 0) {
    return res
      ..sum = 0
      ..cOut = 0;
  } else if (a + b + cIn == 3) {
    return res
      ..sum = 1
      ..cOut = 1;
  } else if (a + b + cIn == 1) {
    return res
      ..sum = 1
      ..cOut = 0;
  } else {
    return res
      ..sum = 0
      ..cOut = 1;
  }
}

class FullAdderModule extends Module {
  FullAdderModule(
    Logic a,
    Logic b,
    Logic cIn,
    void Function(
            Logic a, Logic b, Logic cIn, Logic xorAB, Logic sum, Logic cOut)
        faOps,
  ) : super(name: 'full_adder') {
    a = addInput('a', a);
    b = addInput('b', b);
    cIn = addInput('c_in', cIn);

    final sum = addOutput('sum');
    final cOut = addOutput('c_out');

    final xorAB = Logic(name: 'xor_ab');
    faOps(a, b, cIn, xorAB, sum, cOut);
  }
}

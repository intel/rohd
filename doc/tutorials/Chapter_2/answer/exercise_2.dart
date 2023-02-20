import 'package:rohd/rohd.dart';
import '../helper.dart';

// ignore_for_file: avoid_print, unnecessary_this

// TODO(user): (Optional) Change [YourModuleName] to your own module name.
class Exercise2 extends Module {
  late final Logic a;
  late final Logic b;
  late final Logic c;

  // TODO(user): (Optional) 'ModuleName' can change to your own module name.
  Exercise2() : super(name: 'Exercise2') {
    // TODO(user): (Required) Paste your Logic initialization here.

    // Create input and output signals
    // Note that we don't need final here as we are using global variable.
    // Dart is smart enough to assume the following a, b, c variable without
    // this.a, but I will be using this to make the code more clear.
    a = Logic(name: 'input_a');
    b = Logic(name: 'input_b');
    c = Logic(name: 'output_c');

    // TODO(user): (Required) Declare your input and output port.
    final signal1 = addInput('input_a', a, width: a.width);
    final signal2 = addInput('input_b', b, width: b.width);
    final signal3 = addOutput('output_c');

    // Note: If you're familiar with SV, you may want to read this section,
    // but if it's new to you, feel free to skip ahead.
    // We'll cover the topic more extensively in Chapters 5, 6, and 7,
    // where you'll have the opportunity to gain a deeper understanding.
    const answer = 'xor'; // 'or', 'nor', 'xor'
    switch (answer) {
      case 'or':
        c <= signal1 | signal2;
        break;
      case 'nor':
        c <= ~(signal1 | signal2);
        break;
      case 'xor':
        c <= signal1 ^ signal2;
        break;
    }

    signal3 <= c;
  }
}

Future<void> main() async {
  // Instantiate Module and display system verilog.
  // TODO(user): (Optional) Update [YourModuleName].
  final basicLogic = Exercise2();
  await displaySystemVerilog(basicLogic);

  // Note: Make sure `generateTruthTable` is false when want to generate
  // system verilog code.
  const generateTruthTable = true;
  if (generateTruthTable) {
    print('\nGenerate Logic Gate: ');
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        basicLogic.a.put(i);
        basicLogic.b.put(j);
        print('a: $i, b: $j c: ${basicLogic.c.value.toInt()}');
      }
    }
  }
}

import 'package:rohd/rohd.dart';
import '../helper.dart';
// ignore_for_file: avoid_print

// TODO(user): (Optional) Change [YourModuleName] to your own module name.
class YourModuleName extends Module {
  // TODO(user): (Optional) 'ModuleName' can change to your own module name.
  YourModuleName() : super(name: 'ModuleName') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // Create input and output signals
    final a = Logic(name: 'input_a');
    final b = Logic(name: 'input_b');
    final c = Logic(name: 'output_c');

    const answer = 'xor'; // 'or', 'nor', 'xor'
    switch (answer) {
      case 'or':
        c <= a | b;
        break;
      case 'nor':
        c <= ~(a | b);
        break;
      case 'xor':
        c <= a ^ b;
        break;
    }

    print('Generate Logic Gate: ');
    for (var i = 0; i <= 1; i++) {
      for (var j = 0; j <= 1; j++) {
        a.put(i);
        b.put(j);
        print('a: $i, b: $j c: ${c.value.toInt()}');
      }
    }

    // TODO(user): (Required) Declare your input and output port.
    final signal1 = addInput('input_a', a);
    final signal2 = addInput('input_b', b);
    final signal3 = addOutput('output_c');

    // Note: If you're familiar with SV, you may want to read this section,
    // but if it's new to you, feel free to skip ahead.
    // We'll cover the topic more extensively in Chapters 5, 6, and 7,
    // where you'll have the opportunity to gain a deeper understanding.
    Logic operation;
    switch (answer) {
      case 'or':
        operation = signal1 | signal2;
        break;
      case 'nor':
        operation = ~(signal1 | signal2);
        break;
      case 'xor':
        operation = signal1 ^ signal2;
        break;
      default:
        operation = signal1 & signal2;
        break;
    }

    Combinational([signal3 < operation]);
  }
}

void main() async {
  // Instantiate Module and display system verilog.
  // TODO(user): (Optional) Update [YourModuleName] .
  final basicLogic = YourModuleName();
  await displaySystemVerilog(basicLogic);
}

// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import '../helper.dart';

// TODO(user): (Optional) Change [YourModuleName] to your own module name.
class YourModuleName extends Module {
  // TODO(user): (Optional) 'ModuleName' can change to your own module name.
  YourModuleName() : super(name: 'ModuleName') {
    // TODO(user): (Required) Paste your Logic initialization here.
    final a = Const(10, width: 4); // 10 in binary is 1010
    final b = Logic(name: 'copy_of_const', width: a.width);

    // TODO(user): (Required) Declare your input and output port.
    final signal2 = addOutput('b', width: b.width);

    b <= a;

    print('Value of b is: ${b.value.toInt()}');

    signal2 <= b;
  }
}

Future<void> main() async {
  // Instantiate Module and display system verilog.
  // TODO(user): (Optional) Update [YourModuleName] .
  final basicLogic = YourModuleName();
  await displaySystemVerilog(basicLogic);
}

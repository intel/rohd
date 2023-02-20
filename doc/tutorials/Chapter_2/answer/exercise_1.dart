// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import '../helper.dart';

// TODO(user): (Optional) Change [YourModuleName] to your own module name.
class YourModuleName extends Module {
  // TODO(user): (Optional) 'ModuleName' can change to your own module name.
  YourModuleName() : super(name: 'ModuleName') {
    // TODO(user): (Required) Paste your Logic initialization here.
    // 1. Create a 3-bit bus signal named `threeBitBus`.
    final threeBitBus = Logic(name: 'threeBitBus');
    print('answer 1: $threeBitBus');

    // 2.Print the output of the signal.
    // Explain what you see.
    // Is there enough information in the output to verify
    // that you have created the correct signal?
    print('answer 2: Yes, threeBitBus Logic property output '
        'the name as threeBitBus. Check threeBitBus.name to see a more simple '
        'answer');

    // TODO(user): (Required) Declare your input and output port.
    final signal1 = addInput('threeBitBus', threeBitBus);
  }
}

void main() async {
  // Instantiate Module and display system verilog.
  // TODO(user): (Optional) Update [YourModuleName] .
  final basicLogic = YourModuleName();
  await displaySystemVerilog(basicLogic);
}

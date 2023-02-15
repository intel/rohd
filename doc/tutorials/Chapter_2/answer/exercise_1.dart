// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

void main() {
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
}

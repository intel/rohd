import 'dart:io';

import 'package:rohd/rohd.dart';

// ignore_for_file: avoid_print

void main() {
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

  for (var i = 0; i <= 1; i++) {
    for (var j = 0; j <= 1; j++) {
      a.put(i);
      b.put(j);
      print('a: $i, b: $j c: ${c.value.toInt()}');
    }
  }
}

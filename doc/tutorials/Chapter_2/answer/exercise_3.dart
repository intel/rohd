import 'package:rohd/rohd.dart';

// ignore_for_file: avoid_print

void main() {
  final a = Const(10, width: 4); // 10 in binary is 1010
  final b = Logic(name: 'copy_of_const', width: a.width);

  b <= a;

  print('value b Int = ${b.value.toInt()}');
  print('value b String = ${b.value.toString(includeWidth: false)}');
}

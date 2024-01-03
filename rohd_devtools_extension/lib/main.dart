import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/view/stack_overflow_ask.dart';
import 'src/modules/rohd_devtools_module.dart';

void main() {
  runApp(ProviderScope(
    child: RohdDevToolsModule(),
  ));
}

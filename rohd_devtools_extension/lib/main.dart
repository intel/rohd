import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/modules/tree_structure/view/rohd_devtools_extension.dart';

void main() {
  runApp(const ProviderScope(
    child: RohdDevToolsExtension(),
  ));
}

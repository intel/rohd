import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/modules/rohd_devtools_module.dart';

void main() {
  runApp(const ProviderScope(
    child: RohdDevToolsModule(),
  ));
}

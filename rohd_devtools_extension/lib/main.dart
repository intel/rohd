// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Entry point for main application.
//
// 2025 January 28

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/view/rohd_devtools_page.dart';
// import 'package:rohd_devtools_extension/app.dart';

import 'package:rohd_devtools_extension/rohd_devtools_observer.dart';

void main() {
  /// Initializing the [BlocObserver] created and calling runApp
  Bloc.observer = const RohdDevToolsObserver();

  runApp(const RohdDevToolsApp());
}

class RohdDevToolsApp extends StatelessWidget {
  const RohdDevToolsApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RohdDevToolsPage(),
    );
  }
}

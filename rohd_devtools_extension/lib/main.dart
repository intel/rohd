// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Main entry for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/view/rohd_devtools_page.dart';

import 'package:rohd_devtools_extension/rohd_devtools_observer.dart';

/// Entry point for the DevTools extension app.
void main() {
  Bloc.observer = const RohdDevToolsObserver();

  runApp(const RohdDevToolsApp());
}

/// Top-level app widget for the DevTools extension.
class RohdDevToolsApp extends StatelessWidget {
  /// Creates the DevTools app.
  const RohdDevToolsApp({super.key});

  @override

  /// Builds the DevTools extension host widget tree.
  Widget build(BuildContext context) => const DevToolsExtension(
        child: RohdDevToolsPage(),
      );
}

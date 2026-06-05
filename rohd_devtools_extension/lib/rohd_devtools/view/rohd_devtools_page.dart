// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_page.dart
// Page view for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_theme.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

/// Main page for the embedded ROHD DevTools experience.
class RohdDevToolsPage extends StatelessWidget {
  /// Creates the DevTools page.
  const RohdDevToolsPage({super.key});

  @override

  /// Builds the themed DevTools page and its bloc providers.
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => DevToolsThemeCubit()),
          BlocProvider(create: (context) => RohdServiceCubit()),
          BlocProvider(create: (context) => TreeSearchTermCubit()),
          BlocProvider(create: (context) => SelectedModuleCubit()),
          BlocProvider(create: (context) => SignalSearchTermCubit()),
          BlocProvider(create: (context) => DetailsTabCubit()),
          BlocProvider(create: (context) => SnapshotCubit()),
        ],
        child: BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
          builder: (context, themeMode) {
            final theme = themeMode == DevToolsThemeMode.dark
                ? buildDarkTheme()
                : buildLightTheme();

            return Theme(data: theme, child: const RohdExtensionModule());
          },
        ),
      );
}

/// Extension module wrapper used by the DevTools host.
class RohdExtensionModule extends StatefulWidget {
  /// Creates the extension module.
  const RohdExtensionModule({super.key});

  @override

  /// Creates the module state.
  State<RohdExtensionModule> createState() => _RohdExtensionModuleState();
}

class _RohdExtensionModuleState extends State<RohdExtensionModule> {
  @override

  /// Builds the module scaffold and tree view.
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: const DevtoolAppBar(),
      body: TreeStructurePage(screenSize: screenSize),
    );
  }
}

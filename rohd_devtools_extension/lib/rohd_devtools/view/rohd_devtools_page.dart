// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_view.dart
// Main view for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtool_appbar.dart';

class RohdDevToolsPage extends StatelessWidget {
  const RohdDevToolsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => RohdServiceCubit(),
        ),
        BlocProvider(
          create: (context) => TreeSearchTermCubit(),
        ),
        BlocProvider(
          create: (context) => SelectedModuleCubit(),
        ),
        BlocProvider(
          create: (context) => SignalSearchTermCubit(),
        ),
      ],
      child: const RohdExtensionModule(),
    );
  }
}

class RohdExtensionModule extends StatefulWidget {
  const RohdExtensionModule({super.key});

  @override
  State<RohdExtensionModule> createState() => _RohdExtensionModuleState();
}

class _RohdExtensionModuleState extends State<RohdExtensionModule> {
  late final EvalOnDartLibrary rohdControllerEval;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: const DevtoolAppBar(),
      body: TreeStructurePage(
        screenSize: screenSize,
      ),
    );
  }
}

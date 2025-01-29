// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_page.dart
// Main page for the app.
//
// 2025 January 28

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';

/// A [StatelessWidget] which is responsible for providing a
/// [RohdDevToolsCubit] instance to the [RohdDevToolsView].
class RohdDevToolsPage extends StatelessWidget {
  const RohdDevToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RohdDevToolsCubit(),
      child: const RohdDevToolsView(
        screenSize: Size(1200, 800),
      ),
    );
  }
}

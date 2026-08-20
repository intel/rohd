// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_details_navbar_test.dart
// Tests for module detail navigation interactions.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/details_tab_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_details_navbar.dart';

void main() {
  testWidgets('selects each details view from its matching navigation tab',
      (tester) async {
    final cubit = DetailsTabCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(
            body: ModuleTreeDetailsNavbar(hasColorEmoji: false),
          ),
        ),
      ),
    );

    expect(cubit.state, DetailsTab.details);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Waveform'), findsOneWidget);
    expect(find.text('Schematic'), findsOneWidget);

    await tester.tap(find.text('Waveform'));
    await tester.pump();
    expect(cubit.state, DetailsTab.waveform);

    await tester.tap(find.text('Schematic'));
    await tester.pump();
    expect(cubit.state, DetailsTab.schematic);

    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(cubit.state, DetailsTab.details);
  });
}

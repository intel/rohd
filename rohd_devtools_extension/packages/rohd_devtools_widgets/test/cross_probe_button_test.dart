// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cross_probe_button_test.dart
// Tests for the cross-probing toolbar toggle button.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  testWidgets('toggles cross-probing service active state', (tester) async {
    final channel = LocalCrossProbeChannel();
    final service = LocalCrossProbeService(channel, source: 'waveform');
    addTearDown(service.dispose);
    addTearDown(channel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            useMaterial3: false, splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: CrossProbeButton(service: service),
        ),
      ),
    );

    expect(service.isActive.value, isTrue);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Cross-probing active — tap to disable',
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(service.isActive.value, isFalse);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Cross-probing disabled — tap to enable',
    );
  });
}

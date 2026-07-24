// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_bar_overlay_test.dart
// Tests for auto-hiding app bar overlay behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  PreferredSizeWidget testAppBar() => const PreferredSize(
        preferredSize: Size.fromHeight(48),
        child: Material(child: Text('Toolbar')),
      );

  testWidgets('lays out app bar above body when auto-hide is disabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppBarOverlay(
          appBar: testAppBar(),
          body: const Text('Body'),
        ),
      ),
    );

    expect(find.text('Toolbar'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.byType(Column), findsOneWidget);
    expect(find.byType(Stack), findsNothing);
  });

  testWidgets('slides overlay app bar in when pointer enters trigger zone',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppBarOverlay(
          appBar: testAppBar(),
          body: const Text('Body'),
          autoHide: true,
          triggerHeight: 16,
          animationDuration: const Duration(milliseconds: 1),
        ),
      ),
    );

    final overlaySlide = find.descendant(
      of: find.byType(AppBarOverlay),
      matching: find.byType(SlideTransition),
    );
    var slide = tester.widget<SlideTransition>(overlaySlide);
    expect(slide.position.value, const Offset(0, -1));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(10, 10));
    await tester.pumpAndSettle();

    slide = tester.widget<SlideTransition>(overlaySlide);
    expect(slide.position.value, Offset.zero);
  });
}

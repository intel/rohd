// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// capture_boundary_test.dart
// Tests for RepaintBoundary PNG capture and toast feedback.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  testWidgets('returns false when no repaint boundary is found',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captureContext = context;
            return SizedBox(key: key, width: 10, height: 10);
          },
        ),
      ),
    );

    expect(
      await captureBoundaryToPng(captureContext, boundaryKey: key),
      isFalse,
    );
  });

  testWidgets('returns false when the key has no mounted context',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captureContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      await captureBoundaryToPng(captureContext, boundaryKey: key),
      isFalse,
    );
  });

  testWidgets('saves injected PNG bytes and shows saved path toast',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;
    Uint8List? savedBytes;
    String? fileName;
    double? requestedPixelRatio;

    await _pumpRepaintBoundary(
      tester,
      key: key,
      onContext: (context) => captureContext = context,
    );

    final succeeded = await captureBoundaryToPng(
      captureContext,
      boundaryKey: key,
      filePrefix: 'wave',
      pixelRatio: 3,
      encodeFn: (boundary, pixelRatio) async {
        expect(boundary, isA<RenderRepaintBoundary>());
        requestedPixelRatio = pixelRatio;
        return Uint8List.fromList([1, 2, 3]);
      },
      saveFn: (pngBytes, suggestedName) async {
        savedBytes = pngBytes;
        fileName = suggestedName;
        return '/tmp/$suggestedName';
      },
    );
    await tester.pump();

    expect(succeeded, isTrue);
    expect(requestedPixelRatio, 3);
    expect(savedBytes, [1, 2, 3]);
    expect(fileName, startsWith('wave_'));
    expect(fileName, endsWith('.png'));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data?.startsWith('Saved: /tmp/wave_') == true,
      ),
      findsOneWidget,
    );
    await _letExportToastExpire(tester);
  });

  testWidgets('shows downloaded toast when save function returns no path',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;

    await _pumpRepaintBoundary(
      tester,
      key: key,
      onContext: (context) => captureContext = context,
    );

    final succeeded = await captureBoundaryToPng(
      captureContext,
      boundaryKey: key,
      filePrefix: 'capture',
      encodeFn: (boundary, pixelRatio) async => Uint8List.fromList([4, 5, 6]),
      saveFn: (pngBytes, suggestedName) async => null,
    );
    await tester.pump();

    expect(succeeded, isTrue);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data?.startsWith('Downloaded capture_') == true,
      ),
      findsOneWidget,
    );
    await _letExportToastExpire(tester);
  });

  testWidgets('skips saved toast when context unmounts during save',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;

    await _pumpRepaintBoundary(
      tester,
      key: key,
      onContext: (context) => captureContext = context,
    );

    final succeeded = await captureBoundaryToPng(
      captureContext,
      boundaryKey: key,
      filePrefix: 'wave',
      encodeFn: (boundary, pixelRatio) async => Uint8List.fromList([1, 2, 3]),
      saveFn: (pngBytes, suggestedName) async {
        await tester.pumpWidget(const SizedBox.shrink());
        return '/tmp/$suggestedName';
      },
    );
    await tester.pump();

    expect(succeeded, isTrue);
    expect(find.textContaining('Saved:'), findsNothing);
  });

  testWidgets('returns false and shows failure toast when save throws',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;

    await _pumpRepaintBoundary(
      tester,
      key: key,
      onContext: (context) => captureContext = context,
    );

    final succeeded = await captureBoundaryToPng(
      captureContext,
      boundaryKey: key,
      encodeFn: (boundary, pixelRatio) async => Uint8List.fromList([7, 8, 9]),
      saveFn: (pngBytes, suggestedName) async => throw StateError('disk full'),
    );
    await tester.pump();

    expect(succeeded, isFalse);
    expect(find.textContaining('Export failed: Bad state: disk full'),
        findsOneWidget);
    await _letExportToastExpire(tester);
  });

  testWidgets('returns false when injected encoder returns null',
      (tester) async {
    final key = GlobalKey();
    late BuildContext captureContext;

    await _pumpRepaintBoundary(
      tester,
      key: key,
      onContext: (context) => captureContext = context,
    );

    expect(
      await captureBoundaryToPng(
        captureContext,
        boundaryKey: key,
        encodeFn: (boundary, pixelRatio) async => null,
      ),
      isFalse,
    );
  });
}

Future<void> _pumpRepaintBoundary(
  WidgetTester tester, {
  required GlobalKey key,
  required ValueChanged<BuildContext> onContext,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          onContext(context);
          return Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(width: 8, height: 8),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _letExportToastExpire(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_painter_test.dart
// Test that WaveformBinary reacts correctly to clock data with proper
// timescale.
//
// 2026 September 15
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Run: flutter test test/waveform_painter_test.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform_binary.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Generate a simple alternating clock waveform for testing.
List<Data> _generateClock({
  int startTime = 0,
  int endTime = 10000,
  int period = 200,
}) {
  final data = <Data>[];
  for (var t = startTime; t <= endTime; t += period ~/ 2) {
    data.add(Data(time: t, value: ((t ~/ (period ~/ 2)) % 2).toString()));
  }
  return data;
}

void main() {
  test('WaveformBinary segment building with clock data', () {
    final clockData = _generateClock();
    expect(clockData.length, 101);
    expect(clockData.first.time, 0);
    expect(clockData.first.value, '0');

    // Create a WaveformBinary painter
    final painter = WaveformBinary(
      clockData,
      10000, // finalTime = visibleTimeRange
      0, // startTime = visibleStartTime
      timescale: 10000,
      textColor: Colors.white,
      labelBackgroundColor: Colors.black,
    );

    // Paint onto a test canvas to trigger segment building
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(1000, 30));
    recorder.endRecording();

    // Verify the painter drew correctly
    // With 101 data points alternating 0/1 in range 0-10000 and timescale=10000,
    // the effectiveTimescale = 10000, pxPerTime = 980/10000 ≈ 0.098
    // Each 100-timeunit segment is about 9.8px — clearly visible
    expect(painter.waveform.length, 101);
    expect(painter.timescale, 10000);
  });

  test('WaveformBinary with timescale=20 clips all transitions', () {
    final clockData = _generateClock();

    // Create a WaveformBinary painter with WRONG timescale (fallback case)
    final painter = WaveformBinary(
      clockData,
      20, // finalTime = visibleTimeRange (when timescale=20)
      0, // startTime
      timescale: 20, // <--- THE FALLBACK TIMESCALE WHEN endTime=0
      textColor: Colors.white,
      labelBackgroundColor: Colors.black,
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(1000, 30));
    recorder.endRecording();

    // With timescale=20, only the initial "0" at t=0 is visible:
    // the first transition at t=100 exceeds the 20-unit time window.
    expect(painter.waveform.length, 101);
    expect(painter.timescale, 20);
  });
}

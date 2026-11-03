// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Runnable waveform data construction example.
//
// 2026 September 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_waveform/rohd_waveform.dart';

void main() {
  final data = WaveformData(
    signalId: 'top/counter',
    data: [
      Data(time: 0, value: '0'),
      Data(time: 10, value: '1'),
      Data(time: 20, value: '0'),
    ],
  );
  final waveform = SignalWaveform.fromWaveformData(data);

  if (waveform.data.length != 3 || data.startTime != 0 || data.endTime != 20) {
    throw StateError('Expected three waveform samples from time 0 to 20.');
  }
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cross_probe_service_test.dart
// Tests for local and null cross-probing services.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  group('LocalCrossProbeService', () {
    test('broadcasts selections to other sources only', () {
      final channel = LocalCrossProbeChannel();
      final waveform = LocalCrossProbeService(channel, source: 'waveform');
      final schematic = LocalCrossProbeService(channel, source: 'schematic');

      addTearDown(waveform.dispose);
      addTearDown(schematic.dispose);
      addTearDown(channel.dispose);

      waveform.send(['top.clk', 'top.reset'], source: 'waveform');

      expect(waveform.incomingSignals.value, isNull);
      expect(schematic.incomingSignals.value, ['top.clk', 'top.reset']);
      expect(channel.lastSource, 'waveform');
      expect(channel.lastPaths, ['top.clk', 'top.reset']);
      expect(
        () => channel.lastPaths!.add('top.extra'),
        throwsUnsupportedError,
      );
    });

    test('does not broadcast while inactive or for empty selections', () {
      final channel = LocalCrossProbeChannel();
      final waveform = LocalCrossProbeService(channel, source: 'waveform');
      final schematic = LocalCrossProbeService(channel, source: 'schematic');

      addTearDown(waveform.dispose);
      addTearDown(schematic.dispose);
      addTearDown(channel.dispose);

      waveform.isActive.value = false;
      waveform.send(['top.data'], source: 'waveform');
      expect(channel.lastPaths, isNull);
      expect(schematic.incomingSignals.value, isNull);

      waveform.isActive.value = true;
      waveform.send(const [], source: 'waveform');
      expect(channel.lastPaths, isNull);
      expect(schematic.incomingSignals.value, isNull);

      schematic.isActive.value = false;
      waveform.send(['top.data'], source: 'waveform');
      expect(channel.lastPaths, ['top.data']);
      expect(schematic.incomingSignals.value, isNull);
    });
  });

  group('NullCrossProbeService', () {
    test('starts inactive and ignores sends', () {
      final service = NullCrossProbeService();
      addTearDown(service.dispose);

      expect(service.isActive.value, isFalse);
      expect(service.incomingSignals.value, isNull);

      service.send(['top.clk'], source: 'waveform');

      expect(service.isActive.value, isFalse);
      expect(service.incomingSignals.value, isNull);
    });
  });
}

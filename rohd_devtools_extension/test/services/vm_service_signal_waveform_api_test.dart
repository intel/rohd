// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_transport.dart';

class _MockVmServiceTransport extends Mock implements VmServiceTransport {}

class _TestVmServiceSignalWaveformApi extends VmServiceSignalWaveformApi {
  _TestVmServiceSignalWaveformApi(super.vmTransport);

  void trackForTest(List<String> signalIds) => onTrackSignals(signalIds);
}

void main() {
  test('tracks every requested waveform row including signal copies', () {
    final transport = _MockVmServiceTransport();
    final api = _TestVmServiceSignalWaveformApi(transport);
    when(() => transport.trackSignal(any())).thenReturn(null);

    api.trackForTest(['top/a', 'top/a', 'top/b']);

    verify(() => transport.trackSignal('top/a')).called(2);
    verify(() => transport.trackSignal('top/b')).called(1);
  });
}

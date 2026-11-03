// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// debug_session_test.dart
// Tests for the explicit source/netlist/waveform debugging workflow.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _DebugModule extends Module {
  _DebugModule(Logic a) : super(name: 'debug') {
    a = addInput('a', a);
    addOutput('y') <= ~a;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
    WaveformDataService.instance.clear();
    SourceTracer.clear();
  });

  test('ordinary netlist registration does not start waveform recording',
      () async {
    final module = _DebugModule(Logic());
    await module.build();

    final netlist = NetlistService(module);

    expect(NetlistService.current, same(netlist));
    expect(WaveformDataService.instance.isInitialized, isFalse);
    expect(WaveformDataService.instance.isRecording, isFalse);
  });

  test('debug session owns source, netlist, trace, and live wave capture',
      () async {
    final session = DebugSession.start();
    expect(SourceTracer.isActive, isTrue);

    final module = _DebugModule(Logic());
    await module.build();
    session.attach(module);

    expect(session.isAttached, isTrue);
    expect(NetlistService.current, same(session.netlist));
    expect(TraceService.current, same(session.trace));
    expect(SourceTracer.tracesForModule(module), isNotEmpty);
    expect(WaveformDataService.instance.isInitialized, isTrue);
    expect(WaveformDataService.instance.isRecording, isTrue);

    session.close();

    expect(session.isClosed, isTrue);
    expect(NetlistService.current, isNull);
    expect(TraceService.current, isNull);
    expect(SourceTracer.isActive, isFalse);
    expect(WaveformDataService.instance.isInitialized, isFalse);
    expect(WaveformDataService.instance.isRecording, isFalse);
  });

  test('debug session restores services it temporarily replaces', () async {
    final originalModule = _DebugModule(Logic());
    await originalModule.build();
    final originalNetlist = NetlistService(originalModule);
    final originalTrace = TraceService(originalModule);

    final session = DebugSession.start();
    final module = _DebugModule(Logic());
    await module.build();
    session.attach(module);

    expect(NetlistService.current, same(session.netlist));
    expect(TraceService.current, same(session.trace));

    session.close();

    expect(NetlistService.current, same(originalNetlist));
    expect(TraceService.current, same(originalTrace));
  });
}

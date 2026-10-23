// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// shell_service_test.dart
// Tests cached design command shell invalidation.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _OldDesign extends Module {
  _OldDesign() : super(name: 'old_design') {
    final oldSignal = addInput('old_signal', Logic());
    addOutput('out') <= ~oldSignal;
  }
}

class _NewDesign extends Module {
  _NewDesign() : super(name: 'new_design') {
    final newSignal = addInput('new_signal', Logic());
    addOutput('out') <= ~newSignal;
  }
}

Map<String, Object?> _decodeResponse(String response) =>
    Map<String, Object?>.from(jsonDecode(response) as Map);

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('invalidates command sessions when the netlist changes or disappears',
      () async {
    final oldDesign = _OldDesign();
    await oldDesign.build();
    NetlistService(oldDesign);

    const sessionId = 'shell-service-netlist-invalidation';
    final assignment = _decodeResponse(
      RohdShellService.executeDesignCommandNow(
        sessionId,
        'let old = find-ports .*',
      ),
    );
    expect(assignment['ok'], isTrue);
    expect(
      _decodeResponse(
        RohdShellService.completeDesignCommandNow(sessionId, r'$', 1),
      )['items'],
      [r'$old'],
    );

    final newDesign = _NewDesign();
    await newDesign.build();
    NetlistService(newDesign);

    expect(
      _decodeResponse(
        RohdShellService.completeDesignCommandNow(sessionId, r'$', 1),
      )['items'],
      isEmpty,
    );
    final newSignal = _decodeResponse(
      RohdShellService.executeDesignCommandNow(sessionId, 'find-ports .*'),
    );
    expect(newSignal['result'], isA<Map<Object?, Object?>>());
    expect(
      _decodeResponse(
        RohdShellService.executeDesignCommandNow(sessionId, r'$old'),
      )['error'],
      isA<Map<Object?, Object?>>(),
    );

    ModuleServices.instance.reset();
    expect(
      _decodeResponse(
        RohdShellService.completeDesignCommandNow(sessionId, r'$', 1),
      )['error'],
      isA<Map<Object?, Object?>>(),
    );

    final replacement = _NewDesign();
    await replacement.build();
    NetlistService(replacement);
    expect(
      _decodeResponse(
        RohdShellService.executeDesignCommandNow(sessionId, r'$old'),
      )['error'],
      isA<Map<Object?, Object?>>(),
    );
  });
}

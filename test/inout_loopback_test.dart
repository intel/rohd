// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// inout_loopback_test.dart
// Test for the inOut loopback bug: when the same internal net is connected
// to multiple inOut ports on a single submodule, the wire declaration must
// be preserved in the generated SV.

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// A submodule with input, output, AND two inOut ports.
/// The input/output ensure the submodule is discovered by build().
/// The two inOut ports exercise the loopback scenario.
class _SubWithDualInOut extends Module {
  _SubWithDualInOut(Logic inp, LogicNet busA, LogicNet busB)
      : super(
            name: 'sub_dual_inout',
            definitionName: 'SubWithDualInOut') {
    inp = addInput('inp', inp);
    addOutput('out') <= inp;
    addInOut('portA', busA, width: busA.width);
    addInOut('portB', busB, width: busB.width);
  }
}

/// Top module: creates an internal LogicNet not exposed as a port, and
/// passes that same net to both inOut ports of the submodule.
///
/// The net uses an unpreferred name (underscore prefix) so that the
/// synthesis optimizer considers it clearable/mergeable.  With a
/// "renameable" name the optimizer short-circuits before reaching the
/// code path that the patch protects.
///
/// Bug: after passing through `isClearable`, the optimizer sees the
/// internal net connects to only one submodule
/// (`numSubModulesConnected == 1`) and has no other internal connections
/// (`anyInternalConnections == false`), so it removes the wire
/// declaration.  But the wire is needed because both `.portA(net)` and
/// `.portB(net)` reference it in the instantiation.
class _LoopbackTop extends Module {
  _LoopbackTop(Logic inp) : super(name: 'loopback_top') {
    inp = addInput('inp', inp);
    final out = addOutput('out');

    // Internal net — not a port of this module.
    // Underscore prefix → Naming.mergeable → isClearable == true,
    // which lets the signal reach the net-reduction code path.
    final sharedNet = LogicNet(name: '_sharedNet', width: 8);

    // Submodule found via inp/out; sharedNet goes to both inOuts.
    final sub = _SubWithDualInOut(inp, sharedNet, sharedNet);
    out <= sub.output('out');
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('inOut loopback: wire declaration preserved in generated SV', () async {
    final inp = Logic(name: 'inp');
    final mod = _LoopbackTop(inp);
    await mod.build();

    final sv = mod.generateSynth();

    // The submodule must be instantiated.
    expect(sv, contains('SubWithDualInOut'),
        reason: 'Submodule instantiation must appear');
    expect(sv, contains('.portA('),
        reason: 'portA mapping should appear in instantiation');
    expect(sv, contains('.portB('),
        reason: 'portB mapping should appear in instantiation');

    // Extract what portA and portB map to.
    final portAMatch = RegExp(r'\.portA\((\w+)\)').firstMatch(sv);
    final portBMatch = RegExp(r'\.portB\((\w+)\)').firstMatch(sv);
    expect(portAMatch, isNotNull);
    expect(portBMatch, isNotNull);

    final netNameA = portAMatch!.group(1)!;
    final netNameB = portBMatch!.group(1)!;

    // Both ports should reference the same internal net.
    expect(netNameA, equals(netNameB),
        reason: 'Both inOut ports should map to the same internal net');

    // That net must have a wire declaration (not optimized away).
    expect(sv, contains('wire'),
        reason: 'Internal net "$netNameA" must have a wire declaration '
            'even though only one submodule is connected');
  });
}

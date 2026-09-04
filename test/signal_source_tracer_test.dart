// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_source_tracer_test.dart
// Tests for the SourceTracer utility.
//
// 2026 April 21
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// A simple module with an internal signal and a submodule.
class _InnerModule extends Module {
  _InnerModule(Logic a) : super(name: 'inner') {
    a = addInput('a', a);
    final b = addOutput('b');
    b <= ~a;
  }
}

class _OuterModule extends Module {
  _OuterModule(Logic a) : super(name: 'outer') {
    a = addInput('a', a);
    final b = addOutput('b');

    final intermediate = Logic(name: 'intermediate');
    intermediate <= a;

    final inner = _InnerModule(intermediate);
    b <= inner.output('b');
  }
}

/// A module that uses `.named()` on an expression.
class _NamedModule extends Module {
  _NamedModule(Logic a, Logic b) : super(name: 'namedMod') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');

    final xorResult = (a ^ b).named('xorResult');
    y <= xorResult;
  }
}

/// A module with a LogicArray internal signal.
class _ArrayModule extends Module {
  _ArrayModule(Logic a) : super(name: 'arrayMod') {
    a = addInput('a', a, width: 8);
    final y = addOutput('y', width: 8);

    final arr = LogicArray([2], 4, name: 'myArray');
    arr.elements[0] <= a.getRange(0, 4);
    arr.elements[1] <= a.getRange(4, 8);
    y <= arr.elements.rswizzle();
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    SourceTracer.clear();
  });

  group('SourceTracer', () {
    test('records nothing when disabled', () async {
      // No tracer active — nothing should be recorded.
      final mod = _OuterModule(Logic());
      await mod.build();

      final traces = SourceTracer.tracesForModule(mod);
      expect(traces, isEmpty);
    });

    test('records signal traces when enabled', () async {
      SourceTracer.activate();
      final mod = _OuterModule(Logic());
      await mod.build();

      // Should have traces for inputs, outputs, and internal signals
      final traces = SourceTracer.tracesForModule(mod);
      expect(traces, isNotEmpty);

      // The 'intermediate' internal signal should have a trace
      final intermediateTrace = SourceTracer.traceOf(mod, 'intermediate');
      expect(intermediateTrace, isNotNull);
      expect(
        intermediateTrace.toString(),
        contains('signal_source_tracer_test.dart'),
      );
    });

    test('records module traces for submodules', () async {
      SourceTracer.activate();
      final mod = _OuterModule(Logic());
      await mod.build();

      // The inner submodule should have a trace
      expect(mod.subModules, isNotEmpty);
      final innerName = mod.subModules.first.uniqueInstanceName;
      final innerTrace = SourceTracer.traceOf(mod, innerName);
      expect(innerTrace, isNotNull);
      expect(innerTrace.toString(), contains('signal_source_tracer_test.dart'));
    });

    test('traces from .named() capture the call site', () async {
      SourceTracer.activate();
      final mod = _NamedModule(Logic(), Logic());
      await mod.build();

      final xorTrace = SourceTracer.traceOf(mod, 'xorResult');
      expect(xorTrace, isNotNull);
      expect(xorTrace.toString(), contains('signal_source_tracer_test.dart'));
    });

    test('traces for LogicArray signals', () async {
      SourceTracer.activate();
      final mod = _ArrayModule(Logic(width: 8));
      await mod.build();

      final arrTrace = SourceTracer.traceOf(mod, 'myArray');
      expect(arrTrace, isNotNull);
      expect(arrTrace.toString(), contains('signal_source_tracer_test.dart'));
    });

    test('tracesForHierarchy covers full hierarchy', () async {
      SourceTracer.activate();
      final mod = _OuterModule(Logic());
      await mod.build();

      final allTraces = SourceTracer.tracesForHierarchy(mod);
      expect(allTraces, isNotEmpty);

      // Should contain entries for both the outer and inner module levels
      final outerKeys = allTraces.keys.where((k) => k.startsWith('outer.'));
      expect(outerKeys, isNotEmpty);

      // Should contain entries in the inner submodule hierarchy
      final innerKeys = allTraces.keys.where((k) => k.contains('.inner.'));
      expect(innerKeys, isNotEmpty);
    });

    test('dispose removes all traces', () async {
      SourceTracer.activate();
      final mod = _OuterModule(Logic());
      await mod.build();

      expect(SourceTracer.tracesForModule(mod), isNotEmpty);

      SourceTracer.clear();

      expect(SourceTracer.tracesForModule(mod), isEmpty);
    });

    test('traceOf returns null for unknown address', () async {
      SourceTracer.activate();
      final mod = _OuterModule(Logic());
      await mod.build();

      expect(SourceTracer.traceOf(mod, 'nonexistent'), isNull);
    });
  });
}

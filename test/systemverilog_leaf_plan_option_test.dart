// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_leaf_plan_option_test.dart
// Tests for opt-in SystemVerilog leaf expression plan rendering.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import 'synth_test_helpers.dart';

class _InlineOpsModule extends Module {
  _InlineOpsModule(Logic a, Logic b, Logic control) {
    a = addInput('a', a, width: 4);
    b = addInput('b', b, width: 4);
    control = addInput('control', control);

    final yAnd = addOutput('y_and', width: 4);
    final yNot = addOutput('y_not', width: 4);
    final yMux = addOutput('y_mux', width: 4);

    yAnd <= a & b;
    yNot <= ~a;
    yMux <= mux(control, a, b);
  }
}

class _InlineRangeReplicationModule extends Module {
  _InlineRangeReplicationModule(Logic a) {
    a = addInput('a', a, width: 8);

    final ySubset = addOutput('y_subset', width: 4);
    final yRep = addOutput('y_rep', width: 12);
    final ySwizzle = addOutput('y_swizzle', width: 8);

    final subsetUpper = BusSubset(a, 5, 2).subset;
    final subsetLower = BusSubset(a, 3, 0).subset;
    ySubset <= subsetUpper;
    yRep <= ReplicationOp(subsetLower, 3).replicated;
    ySwizzle <= Swizzle([subsetUpper, subsetLower]).out;
  }
}

class _InlinePowerIndexModule extends Module {
  _InlinePowerIndexModule(Logic a, Logic b, Logic idx) {
    a = addInput('a', a, width: 4);
    b = addInput('b', b, width: 4);
    idx = addInput('idx', idx, width: 2);

    final yPow = addOutput('y_pow', width: 4);
    final yIdx = addOutput('y_idx');

    yPow <= Power(a, b).out;
    yIdx <= IndexGate(a, idx).selection;
  }
}

class _InlineSingleBitEdgesModule extends Module {
  _InlineSingleBitEdgesModule(Logic a, Logic scalar, Logic idx) {
    a = addInput('a', a, width: 4);
    scalar = addInput('scalar', scalar);
    idx = addInput('idx', idx, width: 2);

    final ySubsetSingle = addOutput('y_subset_single');
    final yIdxSingle = addOutput('y_idx_single');

    ySubsetSingle <= BusSubset(a, 2, 2).subset;
    yIdxSingle <= IndexGate(scalar, idx).selection;
  }
}

class _InlineSwizzleZeroWidthModule extends Module {
  _InlineSwizzleZeroWidthModule(Logic a) {
    a = addInput('a', a, width: 4);

    final ySwizzleZero = addOutput('y_swizzle_zero', width: 4);
    ySwizzleZero <= Swizzle([a, Const(0, width: 0)]).out;
  }
}

class _InlineSwizzleCollapsedSelectsModule extends Module {
  _InlineSwizzleCollapsedSelectsModule(Logic a) {
    a = addInput('a', a, width: 8);

    final ySwizzleCollapse = addOutput('y_swizzle_collapse', width: 3);
    ySwizzleCollapse <=
        Swizzle([
          BusSubset(a, 7, 7).subset,
          BusSubset(a, 6, 6).subset,
          BusSubset(a, 5, 5).subset,
        ]).out;
  }
}

class _InlineSwizzlePartialCollapseModule extends Module {
  _InlineSwizzlePartialCollapseModule(Logic a) {
    a = addInput('a', a, width: 8);

    final ySwizzlePartial = addOutput('y_swizzle_partial', width: 3);
    ySwizzlePartial <=
        Swizzle([
          BusSubset(a, 7, 7).subset,
          BusSubset(a, 6, 6).subset,
          BusSubset(a, 4, 4).subset,
        ]).out;
  }
}

class _InlineSwizzleAscendingSelectsModule extends Module {
  _InlineSwizzleAscendingSelectsModule(Logic a) {
    a = addInput('a', a, width: 8);

    final ySwizzleAscending = addOutput('y_swizzle_ascending', width: 3);
    ySwizzleAscending <=
        Swizzle([
          BusSubset(a, 5, 5).subset,
          BusSubset(a, 6, 6).subset,
          BusSubset(a, 7, 7).subset,
        ]).out;
  }
}

class _InlineSwizzleMultiSourceCollapseModule extends Module {
  _InlineSwizzleMultiSourceCollapseModule(Logic a, Logic b) {
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);

    final ySwizzleMultiSource = addOutput('y_swizzle_multi_source', width: 4);
    ySwizzleMultiSource <=
        Swizzle([
          BusSubset(a, 7, 7).subset,
          BusSubset(a, 6, 6).subset,
          BusSubset(b, 3, 3).subset,
          BusSubset(b, 2, 2).subset,
        ]).out;
  }
}

class _InlineSwizzleUnpackedArrayElementsModule extends Module {
  _InlineSwizzleUnpackedArrayElementsModule(LogicArray arr) {
    final inArr = addInputArray(
      'arr',
      arr,
      dimensions: [4],
      numUnpackedDimensions: 1,
    );
    addOutput('y_swizzle_unpacked', width: 4) <=
        inArr.elements.reversed.toList().swizzle();
  }
}

class _InlineMixedOptionGateModule extends Module {
  _InlineMixedOptionGateModule(Logic a, Logic b, Logic control, Logic idx) {
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);
    control = addInput('control', control);
    idx = addInput('idx', idx, width: 3);

    final yAnd = addOutput('y_and', width: 8);
    final yMux = addOutput('y_mux', width: 8);
    final yPow = addOutput('y_pow', width: 8);
    final yIdx = addOutput('y_idx');
    final ySwizzle = addOutput('y_swizzle', width: 8);

    yAnd <= a & b;
    yMux <= mux(control, a, b);
    yPow <= Power(a, b).out;
    yIdx <= IndexGate(a, idx).selection;
    ySwizzle <= Swizzle([a.slice(7, 4), a.slice(3, 0)]).out;
  }
}

void main() {
  test('leaf-expression-plan inline rendering is opt-in', () async {
    final mod = _InlineOpsModule(
      Logic(name: 'a', width: 4),
      Logic(name: 'b', width: 4),
      Logic(name: 'control'),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('assign y_and = a & b;'));
    expect(baseline, contains('assign y_not = ~a;'));
    expect(baseline, contains('assign y_mux = control ? a : b;'));

    expect(planned, contains('assign y_and = a & b;'));
    expect(planned, contains('assign y_not = ~a;'));
    expect(planned, contains('assign y_mux = control ? a : b;'));
  });

  test('opt-in path preserves inline output for range/replication/swizzle',
      () async {
    final mod = _InlineRangeReplicationModule(Logic(name: 'a', width: 8));
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(
      baseline,
      contains(RegExp(r'assign y_subset = \{a\[2\],a\[3\],a\[4\],a\[5\]\};')),
    );
    expect(
      baseline,
      contains(RegExp(r'assign y_rep = \{3\{_subset_0_3_a\}\};')),
    );
    expect(
      baseline,
      contains(RegExp(r'assign y_swizzle = \{\s*y_subset, /\* 7:4 \*/')),
    );

    expect(
      planned,
      contains(RegExp(r'assign y_subset = \{a\[2\],a\[3\],a\[4\],a\[5\]\};')),
    );
    expect(
      planned,
      contains(RegExp(r'assign y_rep = \{3\{_subset_0_3_a\}\};')),
    );
    expect(
      planned,
      contains(RegExp(r'assign y_swizzle = \{\s*y_subset, /\* 7:4 \*/')),
    );
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves inline output for power/index', () async {
    final mod = _InlinePowerIndexModule(
      Logic(name: 'a', width: 4),
      Logic(name: 'b', width: 4),
      Logic(name: 'idx', width: 2),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains(RegExp(r'assign y_pow = \{a \*\* b\};')));
    expect(baseline, contains(RegExp(r'assign y_idx = a\[idx\];')));

    expect(planned, contains(RegExp(r'assign y_pow = \{a \*\* b\};')));
    expect(planned, contains(RegExp(r'assign y_idx = a\[idx\];')));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves inline output for single-bit edge cases',
      () async {
    final mod = _InlineSingleBitEdgesModule(
      Logic(name: 'a', width: 4),
      Logic(name: 'scalar'),
      Logic(name: 'idx', width: 2),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('assign y_subset_single = a[2];'));
    expect(baseline, contains('assign y_idx_single = scalar;'));

    expect(planned, contains('assign y_subset_single = a[2];'));
    expect(planned, contains('assign y_idx_single = scalar;'));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves swizzle output with zero-width input', () async {
    final mod = _InlineSwizzleZeroWidthModule(Logic(name: 'a', width: 4));
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('assign y_swizzle_zero = a;'));
    expect(planned, contains('assign y_swizzle_zero = a;'));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves swizzle contiguous-select collapsing', () async {
    final mod = _InlineSwizzleCollapsedSelectsModule(
      Logic(name: 'a', width: 8),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('assign y_swizzle_collapse = a[7:5];'));
    expect(planned, contains('assign y_swizzle_collapse = a[7:5];'));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves swizzle partial contiguous-collapse', () async {
    final mod = _InlineSwizzlePartialCollapseModule(
      Logic(name: 'a', width: 8),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('a[7:6]'));
    expect(baseline, contains('a[4]'));
    expect(planned, contains('a[7:6]'));
    expect(planned, contains('a[4]'));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves non-collapsible ascending swizzle order',
      () async {
    final mod = _InlineSwizzleAscendingSelectsModule(
      Logic(name: 'a', width: 8),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('a[5]'));
    expect(baseline, contains('a[6]'));
    expect(baseline, contains('a[7]'));
    expect(baseline, isNot(contains('a[7:5]')));

    expect(planned, contains('a[5]'));
    expect(planned, contains('a[6]'));
    expect(planned, contains('a[7]'));
    expect(planned, isNot(contains('a[7:5]')));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves per-source swizzle collapsing', () async {
    final mod = _InlineSwizzleMultiSourceCollapseModule(
      Logic(name: 'a', width: 8),
      Logic(name: 'b', width: 8),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('a[7:6]'));
    expect(baseline, contains('b[3:2]'));
    expect(planned, contains('a[7:6]'));
    expect(planned, contains('b[3:2]'));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves unpacked-array swizzle non-collapse', () async {
    final mod = _InlineSwizzleUnpackedArrayElementsModule(
      LogicArray([4], 1, numUnpackedDimensions: 1),
    );
    await mod.build();

    final baseline = mod.generateSynth();
    final planned = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(baseline, contains('arr[3]'));
    expect(baseline, contains('arr[2]'));
    expect(baseline, contains('arr[1]'));
    expect(baseline, contains('arr[0]'));
    expect(baseline, isNot(contains('arr[3:0]')));

    expect(planned, contains('arr[3]'));
    expect(planned, contains('arr[2]'));
    expect(planned, contains('arr[1]'));
    expect(planned, contains('arr[0]'));
    expect(planned, isNot(contains('arr[3:0]')));
    expect(
      normalizeSynthHeader(planned),
      equals(normalizeSynthHeader(baseline)),
    );
  });

  test('opt-in path preserves swizzle parity matrix', () async {
    final scenarios = <({
      String name,
      Module Function() build,
      List<String> contains,
      List<String> notContains,
    })>[
      (
        name: 'zero-width filtered',
        build: () => _InlineSwizzleZeroWidthModule(
              Logic(name: 'a', width: 4),
            ),
        contains: ['assign y_swizzle_zero = a;'],
        notContains: const [],
      ),
      (
        name: 'contiguous collapse',
        build: () => _InlineSwizzleCollapsedSelectsModule(
              Logic(name: 'a', width: 8),
            ),
        contains: ['assign y_swizzle_collapse = a[7:5];'],
        notContains: const [],
      ),
      (
        name: 'partial collapse',
        build: () => _InlineSwizzlePartialCollapseModule(
              Logic(name: 'a', width: 8),
            ),
        contains: ['a[7:6]', 'a[4]'],
        notContains: const [],
      ),
      (
        name: 'ascending non-collapsible',
        build: () => _InlineSwizzleAscendingSelectsModule(
              Logic(name: 'a', width: 8),
            ),
        contains: ['a[5]', 'a[6]', 'a[7]'],
        notContains: ['a[7:5]'],
      ),
      (
        name: 'multi-source collapse',
        build: () => _InlineSwizzleMultiSourceCollapseModule(
              Logic(name: 'a', width: 8),
              Logic(name: 'b', width: 8),
            ),
        contains: ['a[7:6]', 'b[3:2]'],
        notContains: const [],
      ),
      (
        name: 'unpacked-array non-collapse',
        build: () => _InlineSwizzleUnpackedArrayElementsModule(
              LogicArray([4], 1, numUnpackedDimensions: 1),
            ),
        contains: ['arr[3]', 'arr[2]', 'arr[1]', 'arr[0]'],
        notContains: ['arr[3:0]'],
      ),
    ];

    for (final scenario in scenarios) {
      final mod = scenario.build();
      await mod.build();

      final baseline = mod.generateSynth();
      final planned = mod.generateSynth(
        configuration: const SystemVerilogSynthesizerConfiguration(
          useLeafExpressionPlanForInlineRendering: true,
        ),
      );

      for (final expected in scenario.contains) {
        expect(
          baseline,
          contains(expected),
          reason: 'baseline missing "$expected" for ${scenario.name}',
        );
        expect(
          planned,
          contains(expected),
          reason: 'planned missing "$expected" for ${scenario.name}',
        );
      }

      for (final disallowed in scenario.notContains) {
        expect(
          baseline,
          isNot(contains(disallowed)),
          reason: 'baseline unexpectedly had "$disallowed" for '
              '${scenario.name}',
        );
        expect(
          planned,
          isNot(contains(disallowed)),
          reason: 'planned unexpectedly had "$disallowed" for '
              '${scenario.name}',
        );
      }

      expect(
        normalizeSynthHeader(planned),
        equals(normalizeSynthHeader(baseline)),
        reason: 'full synth mismatch for ${scenario.name}',
      );
    }
  });

  test('default option matches explicit false and opt-in parity on mixed ops',
      () async {
    final mod = _InlineMixedOptionGateModule(
      Logic(name: 'a', width: 8),
      Logic(name: 'b', width: 8),
      Logic(name: 'control'),
      Logic(name: 'idx', width: 3),
    );
    await mod.build();

    final defaultSynth = mod.generateSynth();
    final explicitFalseConfiguration = SystemVerilogSynthesizerConfiguration(
      useLeafExpressionPlanForInlineRendering: [false].single,
    );
    final explicitFalse =
        mod.generateSynth(configuration: explicitFalseConfiguration);
    final optIn = mod.generateSynth(
      configuration: const SystemVerilogSynthesizerConfiguration(
        useLeafExpressionPlanForInlineRendering: true,
      ),
    );

    expect(
      normalizeSynthHeader(defaultSynth),
      equals(normalizeSynthHeader(explicitFalse)),
    );
    expect(
      normalizeSynthHeader(optIn),
      equals(normalizeSynthHeader(defaultSynth)),
    );

    expect(defaultSynth, contains('assign y_and = a & b;'));
    expect(defaultSynth, contains('assign y_mux = control ? a : b;'));
    expect(defaultSynth, contains('assign y_pow = {a ** b};'));
    expect(defaultSynth, contains('assign y_idx = a[idx];'));
  });
}

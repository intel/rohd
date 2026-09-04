// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_session_test.dart
// Tests for ROHD design-session value contracts.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('status retains an immutable capability set', () {
    final source = <RohdDesignCapability>{RohdDesignCapability.hierarchy};
    final status = RohdDesignStatus(
      epoch: const RohdDesignEpoch(3),
      capabilities: source,
      designName: 'counter',
    );
    source.add(RohdDesignCapability.waveform);

    expect(status.epoch, const RohdDesignEpoch(3));
    expect(status.designName, 'counter');
    expect(status.supports(RohdDesignCapability.hierarchy), isTrue);
    expect(status.supports(RohdDesignCapability.waveform), isFalse);
    expect(
      () => status.capabilities.add(RohdDesignCapability.waveform),
      throwsUnsupportedError,
    );
  });

  test('page preserves order and cannot be mutated', () {
    final page = RohdPage<int>(items: [1, 2]);

    expect(page.items, [1, 2]);
    expect(() => page.items.add(3), throwsUnsupportedError);
  });
}

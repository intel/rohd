// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// occurrence_trie_test.dart
// Tests for compact occurrence-address trie storage.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  test('stores values with shared occurrence-address prefixes', () {
    final trie = OccurrenceTrie<String>();
    const first = OccurrenceAddress([0, 2, 4]);
    const second = OccurrenceAddress([0, 2, 5]);

    trie[first] = 'first';
    trie[OccurrenceAddress.root] = 'root';
    trie[second] = 'second';

    expect(trie[OccurrenceAddress.root], 'root');
    expect(trie[first], 'first');
    expect(trie[second], 'second');
    expect(trie[const OccurrenceAddress([0, 2, 6])], isNull);
  });

  test('prunes an address branch after removing its final value', () {
    final trie = OccurrenceTrie<String>();
    const first = OccurrenceAddress([0, 2, 4]);
    const second = OccurrenceAddress([0, 2, 5]);
    trie[first] = 'first';
    trie[second] = 'second';

    expect(trie.remove(first), 'first');
    expect(trie[first], isNull);
    expect(trie[second], 'second');
    expect(trie.remove(second), 'second');
    expect(trie.isEmpty, isTrue);
  });

  test('accepts root addresses and rejects negative path indices', () {
    final trie = OccurrenceTrie<String>();

    trie[OccurrenceAddress.root] = 'root';
    expect(trie[OccurrenceAddress.root], 'root');
    expect(
      () => trie[const OccurrenceAddress([0, -1])],
      throwsArgumentError,
    );
  });
}

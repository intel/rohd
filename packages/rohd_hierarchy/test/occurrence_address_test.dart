// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// occurrence_address_test.dart
// Unit tests for OccurrenceAddress class.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('OccurrenceAddress', () {
    test('child() appends module index', () {
      final addr = OccurrenceAddress.root.child(0).child(2).child(4);
      expect(addr.path, equals([0, 2, 4]));
    });

    test('signal() appends signal index', () {
      final addr = const OccurrenceAddress([0, 1]).signal(5);
      expect(addr.path, equals([0, 1, 5]));
    });

    test('equality and hashcode work correctly', () {
      const addr1 = OccurrenceAddress([0, 2, 4]);
      const addr2 = OccurrenceAddress([0, 2, 4]);
      const addr3 = OccurrenceAddress([0, 2, 5]);

      expect(addr1, equals(addr2));
      expect(addr1.hashCode, equals(addr2.hashCode));
      expect(addr1, isNot(equals(addr3)));
      expect(addr1.hashCode, isNot(equals(addr3.hashCode)));
    });

    test('toString() returns debug string', () {
      expect(OccurrenceAddress.root.toString(), equals('[ROOT]'));
      expect(const OccurrenceAddress([0, 2, 4]).toString(), equals('[0.2.4]'));
    });

    test('toDotString() returns dot-separated path', () {
      expect(OccurrenceAddress.root.toDotString(), equals(''));
      expect(const OccurrenceAddress([0]).toDotString(), equals('0'));
      expect(const OccurrenceAddress([0, 2, 4]).toDotString(), equals('0.2.4'));
      expect(
          const OccurrenceAddress([10, 200]).toDotString(), equals('10.200'));
    });

    test('fromDotString() parses dot-separated path', () {
      expect(
          OccurrenceAddress.fromDotString(''), equals(OccurrenceAddress.root));
      expect(OccurrenceAddress.fromDotString('0'),
          equals(const OccurrenceAddress([0])));
      expect(OccurrenceAddress.fromDotString('0.2.4'),
          equals(const OccurrenceAddress([0, 2, 4])));
      expect(OccurrenceAddress.fromDotString('10.200'),
          equals(const OccurrenceAddress([10, 200])));
    });

    test('toDotString/fromDotString round-trip', () {
      final testCases = [
        OccurrenceAddress.root,
        const OccurrenceAddress([0]),
        const OccurrenceAddress([5, 10, 15]),
        const OccurrenceAddress([0, 0, 0]),
        const OccurrenceAddress([255]),
        const OccurrenceAddress([0, 1, 2, 3, 4, 5]),
      ];
      for (final original in testCases) {
        final dot = original.toDotString();
        final restored = OccurrenceAddress.fromDotString(dot);
        expect(restored, equals(original), reason: 'Failed for $original');
      }
    });
  });

  group('OccurrenceAddress with HierarchyNode integration', () {
    late HierarchyOccurrence root;

    setUp(() {
      // Build a simple tree structure
      final child0 = HierarchyOccurrence(
        name: 'child_0',
        signals: [
          SignalOccurrence(
            name: 'sig0',
            width: 1,
          ),
          SignalOccurrence(
            name: 'sig1',
            width: 8,
          ),
        ],
      );

      final grandchild = HierarchyOccurrence(
        name: 'grandchild_0',
        signals: [
          SignalOccurrence(
            name: 'sig0',
            width: 1,
          ),
        ],
      );

      final child1 = HierarchyOccurrence(
        name: 'child_1',
        signals: [
          SignalOccurrence(
            name: 'sig0',
            width: 4,
          ),
        ],
      );

      child0.children.add(grandchild);

      root = HierarchyOccurrence(
        name: 'root',
        signals: [
          SignalOccurrence(
            name: 'clk',
            width: 1,
          ),
        ],
        children: [child0, child1],
      )
        // Build addresses for all nodes
        ..buildAddresses();
    });

    test('buildAddresses assigns address to root', () {
      expect(root.address, equals(OccurrenceAddress.root));
    });

    test('buildAddresses assigns addresses to all nodes', () {
      expect(root.children[0].address, equals(const OccurrenceAddress([0])));
      expect(root.children[1].address, equals(const OccurrenceAddress([1])));
      expect(root.children[0].children[0].address,
          equals(const OccurrenceAddress([0, 0])));
    });

    test('buildAddresses assigns addresses to all signals', () {
      // Root signals
      expect(root.signals[0].address, equals(const OccurrenceAddress([0])));

      // Child signals
      expect(root.children[0].signals[0].address,
          equals(const OccurrenceAddress([0, 0])));
      expect(root.children[0].signals[1].address,
          equals(const OccurrenceAddress([0, 1])));

      // Grandchild signals
      expect(root.children[0].children[0].signals[0].address,
          equals(const OccurrenceAddress([0, 0, 0])));
    });
  });

  group('HierarchyOccurrence.parent', () {
    test('parent is null for root', () {
      final root = HierarchyOccurrence(name: 'Top')..buildAddresses();
      expect(root.parent, isNull);
    });

    test('parent is set for child nodes after buildAddresses', () {
      final child = HierarchyOccurrence(name: 'sub');
      final root = HierarchyOccurrence(name: 'Top', children: [child])
        ..buildAddresses();
      expect(child.parent, same(root));
      expect(child.path(), 'Top/sub');
    });
  });

  group('HierarchyOccurrence.definition', () {
    test('type is null when not provided', () {
      final n = HierarchyOccurrence(name: 'a');
      expect(n.definition, isNull);
    });

    test('type is stored when provided', () {
      final n = HierarchyOccurrence(name: 'a', definition: 'Counter');
      expect(n.definition, 'Counter');
    });
  });

  group('isPrimitive on nodes', () {
    test('default isPrimitive is false', () {
      final n = HierarchyOccurrence(name: 'sub');
      expect(n.isPrimitive, isFalse);
    });
  });

  group('buildAddresses ports-first ordering', () {
    test('ports get lower signal indices than internal signals', () {
      final root = HierarchyOccurrence(
        name: 'Top',
        signals: [
          SignalOccurrence(name: 'internal_a', width: 8),
          SignalOccurrence(
              name: 'clk', width: 1, direction: 'input', portIndex: 0),
          SignalOccurrence(name: 'internal_b', width: 4),
          SignalOccurrence(
              name: 'out', width: 8, direction: 'output', portIndex: 1),
        ],
      )..buildAddresses();

      final byName = {for (final s in root.signals) s.name: s};

      // Ports should get indices 0 and 1
      expect(byName['clk']!.address, equals(const OccurrenceAddress([0])));
      expect(byName['out']!.address, equals(const OccurrenceAddress([1])));

      // Internal signals get indices 2 and 3
      expect(
          byName['internal_a']!.address, equals(const OccurrenceAddress([2])));
      expect(
          byName['internal_b']!.address, equals(const OccurrenceAddress([3])));
    });

    test('portIndex matches signal address index', () {
      final root = HierarchyOccurrence(
        name: 'Mod',
        signals: [
          SignalOccurrence(
              name: 'a', width: 1, direction: 'input', portIndex: 0),
          SignalOccurrence(
              name: 'b', width: 1, direction: 'input', portIndex: 1),
          SignalOccurrence(
              name: 'y', width: 1, direction: 'output', portIndex: 2),
          SignalOccurrence(name: 'net0', width: 1),
        ],
      )..buildAddresses();

      for (final s in root.signals) {
        if (s.isPort) {
          // portIndex should equal the last element of the address path
          expect(s.address!.path.last, equals(s.portIndex),
              reason: '${s.name}: portIndex=${s.portIndex} '
                  'but address index=${s.address!.path.last}');
        }
      }
    });

    test('portCount returns correct count', () {
      final occ = HierarchyOccurrence(
        name: 'X',
        signals: [
          SignalOccurrence(
              name: 'a', width: 1, direction: 'input', portIndex: 0),
          SignalOccurrence(name: 'b', width: 1),
          SignalOccurrence(
              name: 'c', width: 1, direction: 'output', portIndex: 1),
        ],
      );
      expect(occ.portCount, equals(2));
    });

    test('all-ports occurrence: indices match list order', () {
      final occ = HierarchyOccurrence(
        name: 'Buf',
        signals: [
          SignalOccurrence(
              name: 'in', width: 8, direction: 'input', portIndex: 0),
          SignalOccurrence(
              name: 'out', width: 8, direction: 'output', portIndex: 1),
        ],
      )..buildAddresses();

      expect(occ.signals[0].address, equals(const OccurrenceAddress([0])));
      expect(occ.signals[1].address, equals(const OccurrenceAddress([1])));
    });

    test('all-internal occurrence: indices unchanged', () {
      final occ = HierarchyOccurrence(
        name: 'Internal',
        signals: [
          SignalOccurrence(name: 'x', width: 1),
          SignalOccurrence(name: 'y', width: 1),
        ],
      )..buildAddresses();

      expect(occ.signals[0].address, equals(const OccurrenceAddress([0])));
      expect(occ.signals[1].address, equals(const OccurrenceAddress([1])));
    });

    test('nested: ports-first ordering applies at every level', () {
      final child = HierarchyOccurrence(
        name: 'sub',
        signals: [
          SignalOccurrence(name: 'net', width: 1),
          SignalOccurrence(
              name: 'p', width: 1, direction: 'input', portIndex: 0),
        ],
      );
      final root = HierarchyOccurrence(
        name: 'Top',
        children: [child],
        signals: [
          SignalOccurrence(name: 'net_top', width: 1),
          SignalOccurrence(
              name: 'clk', width: 1, direction: 'input', portIndex: 0),
        ],
      )..buildAddresses();

      // Root: clk (port) at 0, net_top (internal) at 1
      final rootByName = {for (final s in root.signals) s.name: s};
      expect(rootByName['clk']!.address!.path.last, equals(0));
      expect(rootByName['net_top']!.address!.path.last, equals(1));

      // Child: p (port) at 0, net (internal) at 1
      final childByName = {for (final s in child.signals) s.name: s};
      expect(childByName['p']!.address!.path.last, equals(0));
      expect(childByName['net']!.address!.path.last, equals(1));
    });
  });

  group('SignalOccurrence.portIndex', () {
    test('portIndex is null for internal signals', () {
      final s = SignalOccurrence(name: 'net', width: 1);
      expect(s.portIndex, isNull);
      expect(s.isPort, isFalse);
    });

    test('portIndex is set for port signals', () {
      final s = SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
        portIndex: 3,
      );
      expect(s.portIndex, equals(3));
      expect(s.isPort, isTrue);
    });
  });
}

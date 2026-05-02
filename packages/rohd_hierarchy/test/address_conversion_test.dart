// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// address_conversion_test.dart
// Tests for HierarchyService address ↔ pathname conversion methods.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('Address ↔ pathname conversion', () {
    late HierarchyService service;
    late HierarchyNode root;

    // Build a test hierarchy:
    // Top
    //  ├─ cpu (child 0)
    //  │  ├─ signals: clk, rst
    //  │  └─ alu (child 0 of cpu)
    //  │     └─ signals: a, b, out
    //  └─ mem (child 1)
    //     └─ signals: addr, data

    setUpAll(() {
      final alu = HierarchyNode(
        id: 'Top/cpu/alu',
        name: 'alu',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              id: 'a',
              name: 'a',
              type: 'wire',
              width: 1,
              fullPath: 'Top/cpu/alu/a',
              scopeId: 'Top/cpu/alu'),
          Signal(
              id: 'b',
              name: 'b',
              type: 'wire',
              width: 1,
              fullPath: 'Top/cpu/alu/b',
              scopeId: 'Top/cpu/alu'),
          Signal(
              id: 'out',
              name: 'out',
              type: 'wire',
              width: 1,
              fullPath: 'Top/cpu/alu/out',
              scopeId: 'Top/cpu/alu'),
        ],
      );

      final cpu = HierarchyNode(
        id: 'Top/cpu',
        name: 'cpu',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              id: 'clk',
              name: 'clk',
              type: 'wire',
              width: 1,
              fullPath: 'Top/cpu/clk',
              scopeId: 'Top/cpu'),
          Signal(
              id: 'rst',
              name: 'rst',
              type: 'wire',
              width: 1,
              fullPath: 'Top/cpu/rst',
              scopeId: 'Top/cpu'),
        ],
        children: [alu],
      );

      final mem = HierarchyNode(
        id: 'Top/mem',
        name: 'mem',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              id: 'addr',
              name: 'addr',
              type: 'wire',
              width: 1,
              fullPath: 'Top/mem/addr',
              scopeId: 'Top/mem'),
          Signal(
              id: 'data',
              name: 'data',
              type: 'wire',
              width: 1,
              fullPath: 'Top/mem/data',
              scopeId: 'Top/mem'),
        ],
      );

      root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [cpu, mem],
      )..buildAddresses();

      service = BaseHierarchyAdapter.fromTree(root);
    });

    group('pathnameToAddress', () {
      test('root name resolves to root address', () {
        final addr = service.pathnameToAddress('Top');
        expect(addr, isNotNull);
        expect(addr!.path, equals([]));
      });

      test('module path resolves correctly', () {
        final addr = service.pathnameToAddress('Top/cpu');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0]));
      });

      test('nested module path resolves correctly', () {
        final addr = service.pathnameToAddress('Top/cpu/alu');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0, 0]));
      });

      test('second child module resolves correctly', () {
        final addr = service.pathnameToAddress('Top/mem');
        expect(addr, isNotNull);
        expect(addr!.path, equals([1]));
      });

      test('signal path resolves correctly', () {
        final addr = service.pathnameToAddress('Top/cpu/clk');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0, 0])); // cpu[0], signal clk[0]
      });

      test('second signal resolves correctly', () {
        final addr = service.pathnameToAddress('Top/cpu/rst');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0, 1])); // cpu[0], signal rst[1]
      });

      test('nested signal resolves correctly', () {
        final addr = service.pathnameToAddress('Top/cpu/alu/out');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0, 0, 2])); // cpu[0], alu[0], out[2]
      });

      test('dot-separated paths work too', () {
        final addr = service.pathnameToAddress('Top.cpu.alu.b');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0, 0, 1])); // cpu[0], alu[0], b[1]
      });

      test('non-existent path returns null', () {
        expect(service.pathnameToAddress('Top/nonexistent'), isNull);
      });

      test('non-existent signal returns null', () {
        expect(service.pathnameToAddress('Top/cpu/nonexistent'), isNull);
      });

      test('empty string returns root', () {
        final addr = service.pathnameToAddress('');
        expect(addr, isNotNull);
        expect(addr!.path, isEmpty);
      });
    });

    group('addressToPathname', () {
      test('root address returns root name', () {
        expect(
          service.addressToPathname(HierarchyAddress.root),
          equals('Top'),
        );
      });

      test('module address resolves correctly', () {
        expect(
          service.addressToPathname(const HierarchyAddress([0])),
          equals('Top/cpu'),
        );
      });

      test('nested module address resolves correctly', () {
        expect(
          service.addressToPathname(const HierarchyAddress([0, 0])),
          equals('Top/cpu/alu'),
        );
      });

      test('signal address resolves with asSignal flag', () {
        expect(
          service.addressToPathname(
            const HierarchyAddress([0, 0]),
            asSignal: true,
          ),
          equals('Top/cpu/clk'),
        );
      });

      test('nested signal address resolves with asSignal flag', () {
        expect(
          service.addressToPathname(
            const HierarchyAddress([0, 0, 2]),
            asSignal: true,
          ),
          equals('Top/cpu/alu/out'),
        );
      });

      test('out-of-bounds child returns null', () {
        expect(
          service.addressToPathname(const HierarchyAddress([5])),
          isNull,
        );
      });

      test('out-of-bounds signal returns null', () {
        expect(
          service.addressToPathname(
            const HierarchyAddress([0, 99]),
            asSignal: true,
          ),
          isNull,
        );
      });
    });

    group('nodeByAddress', () {
      test('root address returns root', () {
        final node = service.nodeByAddress(HierarchyAddress.root);
        expect(node?.name, equals('Top'));
      });

      test('child address returns correct child', () {
        final node = service.nodeByAddress(const HierarchyAddress([0]));
        expect(node?.name, equals('cpu'));
      });

      test('nested address returns correct node', () {
        final node = service.nodeByAddress(const HierarchyAddress([0, 0]));
        expect(node?.name, equals('alu'));
      });

      test('out-of-bounds returns null', () {
        expect(
          service.nodeByAddress(const HierarchyAddress([99])),
          isNull,
        );
      });
    });

    group('signalByAddress', () {
      test('signal address returns correct signal', () {
        // cpu's first signal (clk) has address [0, 0]
        final clkAddr = root.children[0].signals[0].address!;
        final sig = service.signalByAddress(clkAddr);
        expect(sig?.name, equals('clk'));
      });

      test('nested signal address returns correct signal', () {
        // alu's third signal (out) has address [0, 0, 2]
        final outAddr = root.children[0].children[0].signals[2].address!;
        final sig = service.signalByAddress(outAddr);
        expect(sig?.name, equals('out'));
      });

      test('root address returns null (not a signal)', () {
        expect(service.signalByAddress(HierarchyAddress.root), isNull);
      });
    });

    group('waveformIdToAddress', () {
      test('dot-separated waveform ID resolves', () {
        final addr = service.waveformIdToAddress('Top.cpu.alu.a');
        expect(addr, isNotNull);
        expect(addr!.path, equals([0, 0, 0])); // cpu[0], alu[0], a[0]
      });
    });

    group('round-trip', () {
      test('pathname → address → pathname preserves module path', () {
        const path = 'Top/cpu/alu';
        final addr = service.pathnameToAddress(path);
        expect(addr, isNotNull);
        final roundTripped = service.addressToPathname(addr!);
        expect(roundTripped, equals(path));
      });

      test('pathname → address → pathname preserves signal path', () {
        const path = 'Top/cpu/alu/out';
        final addr = service.pathnameToAddress(path);
        expect(addr, isNotNull);
        final roundTripped = service.addressToPathname(addr!, asSignal: true);
        expect(roundTripped, equals(path));
      });

      test('address → pathname → address preserves module address', () {
        const addr = HierarchyAddress([0, 0]);
        final path = service.addressToPathname(addr);
        expect(path, isNotNull);
        final roundTripped = service.pathnameToAddress(path!);
        expect(roundTripped?.path, equals(addr.path));
      });
    });
  });
}

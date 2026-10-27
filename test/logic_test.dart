// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_test.dart
// Unit tests for `Logic` functionality.
//
// 2025 July 24
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(Simulator.reset);

  group('Logic.from', () {
    for (final isNet in [false, true]) {
      test('creates a connected plain Logic alias with isNet=$isNet', () async {
        final driver = Logic(width: 4)..inject(0xa);
        await Simulator.tick();
        final source = isNet ? (LogicNet(width: 4)..gets(driver)) : driver;
        final alias = Logic.from(source);

        expect(alias, isNot(same(source)));
        expect(alias.runtimeType, Logic);
        expect(alias.isNet, isFalse);
        expect(alias.width, source.width);
        expect(alias.srcConnection, same(source));
        expect(alias.value, LogicValue.ofInt(0xa, 4));

        for (final value in [
          LogicValue.ofInt(0x5, 4),
          LogicValue.ofString('10xz'),
        ]) {
          driver.inject(value);
          await Simulator.tick();
          expect(alias.value, value);
        }

        expect(() => alias.gets(Logic(width: 4)), throwsException);
        expect(() => alias < 0, throwsA(isA<UnassignableException>()));
      });
    }

    test('preserves constant values and immutability', () {
      final source = Const(LogicValue.ofString('10xz'));
      final alias = Logic.from(source);

      expect(alias.runtimeType, Logic);
      expect(alias.width, source.width);
      expect(alias.srcConnection, same(source));
      expect(alias.value, source.value);
      expect(() => alias.put(0), throwsA(isA<UnassignableException>()));
      expect(() => alias.inject(0), throwsA(isA<UnassignableException>()));
      expect(source.value, LogicValue.ofString('10xz'));
    });

    test('packs structures while preserving live connectivity', () async {
      final data = Logic(name: 'data', width: 4);
      final valid = Logic(name: 'valid');
      final source = LogicStructure([data, valid], name: 'payload');
      final alias = Logic.from(source);

      expect(alias.runtimeType, Logic);
      expect(alias.width, 5);
      expect(alias.srcConnection, same(source.packed));

      data.inject(0xa);
      valid.inject(1);
      await Simulator.tick();
      expect(alias.value, LogicValue.ofInt(0x1a, 5));

      data.inject(0x5);
      valid.inject(0);
      await Simulator.tick();
      expect(alias.value, LogicValue.ofInt(0x5, 5));
    });

    test('reuses the source name with mergeable naming by default', () {
      final source = Logic(name: 'source', naming: Naming.reserved);
      final alias = Logic.from(source);

      expect(alias.name, source.name);
      expect(alias.naming, Naming.mergeable);
      expect(source.naming, Naming.reserved);
    });

    test('honors explicit name and naming overrides', () {
      final source = Logic(name: 'source');
      final renamed = Logic.from(source, name: 'source_alias');
      final reserved =
          Logic.from(source, name: 'reserved_alias', naming: Naming.reserved);
      final unnamed = Logic.from(source, naming: Naming.unnamed);

      expect(renamed.name, 'source_alias');
      expect(renamed.naming, Naming.renameable);
      expect(reserved.name, 'reserved_alias');
      expect(reserved.naming, Naming.reserved);
      expect(unnamed.name, source.name);
      expect(unnamed.naming, Naming.unnamed);
    });
  });

  test('packed simple logic returns itself', () {
    final logic = Logic();
    expect(logic.packed, logic);
  });

  test('getRange on filled constants returns a constant', () {
    for (final fillValue in [
      LogicValue.zero,
      LogicValue.one,
      LogicValue.x,
      LogicValue.z,
    ]) {
      final range = Const(LogicValue.filled(8, fillValue)).getRange(2, 5);

      expect(range, isA<Const>());
      expect(range.value, LogicValue.filled(3, fillValue));
      expect(range.parentModule, isNull);
    }
  });

  test('getRange on mixed constants still uses BusSubset', () {
    final range = Const(LogicValue.ofString('10101010')).getRange(2, 5);

    expect(range, isNot(isA<Const>()));
    expect(range.parentModule, isA<BusSubset>());
  });
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// in_process_design_session_test.dart
// Tests for the in-process ROHD design-session implementation.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _SessionLeaf extends Module {
  _SessionLeaf(Logic dataIn)
      : super(name: 'leaf', definitionName: 'SessionLeaf') {
    dataIn = addInput('dataIn', dataIn);
    addOutput('dataOut') <= ~dataIn;
  }
}

class _SessionTop extends Module {
  _SessionTop(Logic dataIn) : super(name: 'top', definitionName: 'SessionTop') {
    dataIn = addInput('dataIn', dataIn);
    final internal = Logic(name: 'internal')..gets(dataIn);
    final leaf = _SessionLeaf(internal);
    addOutput('dataOut') <= leaf.output('dataOut');
  }
}

void main() {
  tearDown(ModuleServices.instance.reset);

  test('inspects and traverses a synthesized design', () async {
    final dut = _SessionTop(Logic(name: 'dataIn'));
    await dut.build();
    final session = InProcessRohdDesignSession(NetlistService(dut));
    const rootPath = 'top';

    final status = await session.status();
    final root = await session.findCell(rootPath);
    final output = await session.findSignal('$rootPath/dataOut');
    final outputPort = await session.findPort('$rootPath/dataOut');
    final internal = await session.findSignal('$rootPath/internal');
    final nonPort = await session.findPort('$rootPath/internal');
    final cells = await session.findCells(
      '.*',
      options: const RohdQueryOptions(pageSize: 1),
    );
    final nextCells = await session.findCells(
      '.*',
      options: RohdQueryOptions(pageSize: 1, pageToken: cells.nextPageToken),
    );
    final signals = await session.findSignals(
      '.*',
      options: const RohdQueryOptions(pageSize: 1),
    );
    final ports = await session.findPorts('.*');
    final nextSignals = await session.findSignals(
      '.*',
      options: RohdQueryOptions(pageSize: 1, pageToken: signals.nextPageToken),
    );
    final fanin = await session.fanin(output!);
    final fanout = await session.fanout(
      (await session.findSignal('$rootPath/dataIn'))!,
    );

    expect(status.supports(RohdDesignCapability.hierarchy), isTrue);
    expect(status.supports(RohdDesignCapability.connectivity), isTrue);
    expect(root, isNotNull);
    expect(identical(root, session.hierarchy.root), isTrue);
    expect(root!.definition, 'SessionTop');
    expect(identical(output.parent, root), isTrue);
    expect(identical(outputPort, output), isTrue);
    expect(internal, isNotNull);
    expect(nonPort, isNull);
    expect(output.width, 1);
    expect(cells.items, hasLength(1));
    expect(nextCells.items, hasLength(1));
    expect(signals.items, hasLength(1));
    expect(nextSignals.items, hasLength(1));
    expect(ports.items, isNotEmpty);
    expect(ports.items.every((port) => port.isPort), isTrue);
    expect(
      nextSignals.items.single.address,
      isNot(signals.items.single.address),
    );
    expect(fanin.items, isNotEmpty);
    expect(fanout.items, isNotEmpty);
  });

  test('rejects invalid paging', () async {
    final dut = _SessionTop(Logic(name: 'dataIn'));
    await dut.build();
    final session = InProcessRohdDesignSession(NetlistService(dut));

    expect(
      session.findCells('.*', options: const RohdQueryOptions(pageSize: 0)),
      throwsArgumentError,
    );
  });

  test('transparent searches return only leaf occurrences', () async {
    final dut = _SessionTop(Logic(name: 'dataIn'));
    await dut.build();
    final session = InProcessRohdDesignSession(NetlistService(dut));

    final cells = await session.findCells('.*', transparent: true);
    final signals = await session.findSignals('.*', transparent: true);

    expect(cells.items, isNotEmpty);
    expect(cells.items.every((cell) => cell.children.isEmpty), isTrue);
    expect(signals.items, isNotEmpty);
    expect(
      signals.items.every((signal) => signal.parent!.children.isEmpty),
      isTrue,
    );
  });

  test(
    'completes hierarchy paths through the shared hierarchy service',
    () async {
      final dut = _SessionTop(Logic(name: 'dataIn'));
      await dut.build();
      final session = InProcessRohdDesignSession(NetlistService(dut));

      expect(await session.completeCellPaths('to'), ['top/']);
      expect(await session.completeCellPaths('top/l'), contains('top/leaf/'));
      expect(
        await session.completeSignalPaths('top/leaf/data'),
        contains('top/leaf/dataIn'),
      );
      expect(await session.completeSignalPaths('top/data'), [
        'top/dataIn',
        'top/dataOut',
      ]);
      final portPaths = await session.completePortPaths('top/');
      expect(portPaths, containsAll(['top/dataIn', 'top/dataOut']));
      expect(portPaths, isNot(contains('top/internal')));
      expect(await session.completePortPaths('to'), ['top/']);
      expect(await session.completePortPaths('top/l'), ['top/leaf/']);
      expect(
        await session.completePortPaths('top/leaf/'),
        containsAll(['top/leaf/dataIn', 'top/leaf/dataOut', 'top/leaf/not_/']),
      );
    },
  );

  test(
    'uses the shared hierarchy regex engine for unqualified searches',
    () async {
      final dut = _SessionTop(Logic(name: 'dataIn'));
      await dut.build();
      final session = InProcessRohdDesignSession(NetlistService(dut));

      final signals = await session.findSignals('dataOut');

      expect(
        signals.items.map((signal) => signal.path()),
        contains('top/dataOut'),
      );
      expect(
        signals.items.map((signal) => signal.path()),
        contains('top/leaf/dataOut'),
      );
    },
  );
}

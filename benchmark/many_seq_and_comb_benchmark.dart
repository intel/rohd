// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// many_seq_and_comb_benchmark.dart
// Benchmarking for a high number of Combinationals and Sequentials connected
// to each other.  Tests performance sensitivity to complex searches.
//
// 2023 April 17
// Based on bug report at https://github.com/intel/rohd/issues/312

import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

enum _MCUInterfaceTag { input, output }

class _MCUInterface extends Interface<_MCUInterfaceTag> {
  _MCUInterface({this.memorySizeOverride}) {
    setPorts([
      Port('clock'),
      Port('enable'),
      Port('write'),
      Port('selectByte'),
      Port('address', 16),
      Port('inputData', 16),
    ], [
      _MCUInterfaceTag.input
    ]);

    setPorts([
      Port('outputData', 16),
    ], [
      _MCUInterfaceTag.output
    ]);
  }

  Logic get clock => port('clock');
  Logic get enable => port('enable');
  Logic get write => port('write');
  Logic get selectByte => port('selectByte');
  Logic get address => port('address');
  Logic get inputData => port('inputData');

  Logic get outputData => port('outputData');

  final int? memorySizeOverride;
}

class _MemoryControllerUnit extends Module {
  _MemoryControllerUnit(_MCUInterface intf) {
    this.intf = _MCUInterface(memorySizeOverride: intf.memorySizeOverride)
      ..connectIO(this, intf,
          inputTags: {_MCUInterfaceTag.input},
          outputTags: {_MCUInterfaceTag.output});

    _buildLogic();
  }

  void _buildLogic() {
    memory = <Logic>[];
    for (var i = 0;
        i < (intf.memorySizeOverride ?? pow(2, intf.address.width));
        ++i) {
      memory.add(Logic(name: 'memoryElement$i', width: 8));
    }

    final writeByteCaseItems = <CaseItem>[];
    final readByteCaseItems = <CaseItem>[];
    final writeHalfwordCaseItems = <CaseItem>[];
    final readHalfwordCaseItems = <CaseItem>[];
    for (var i = 0; i < memory.length; ++i) {
      writeByteCaseItems.add(CaseItem(Const(i, width: intf.address.width),
          [memory[i] < intf.inputData.slice(7, 0)]));
      readByteCaseItems.add(CaseItem(Const(i, width: intf.address.width),
          [intf.outputData < intf.outputData.withSet(0, memory[i])]));

      if (i.isEven) {
        writeHalfwordCaseItems
            .add(CaseItem(Const(i, width: intf.address.width), [
          memory[i] < intf.inputData.slice(7, 0),
          memory[i + 1] < intf.inputData.slice(15, 8)
        ]));
        readHalfwordCaseItems
            .add(CaseItem(Const(i, width: intf.address.width), [
          intf.outputData < [memory[i + 1], memory[i]].swizzle()
        ]));
      }
    }

    Sequential(intf.clock, [
      If(intf.enable, then: [
        If(intf.write, then: [
          If(intf.selectByte,
              then: [Case(intf.address, writeByteCaseItems)],
              orElse: [Case(intf.address, writeHalfwordCaseItems)])
        ], orElse: [
          If(intf.selectByte,
              then: [Case(intf.address, readByteCaseItems)],
              orElse: [Case(intf.address, readHalfwordCaseItems)])
        ])
      ])
    ]);
  }

  late final _MCUInterface intf;
  late final List<Logic> memory;
}

enum ManySeqAndCombCombConnectionType {
  assignments,
  manyCombs,
  oneComb,
  manySsaCombs,
  oneSsaComb
}

class _CombinationalWrapper extends Module {
  final ManySeqAndCombCombConnectionType _combConnectionType;
  late final _MCUInterface intf;

  _CombinationalWrapper(_MCUInterface intf, this._combConnectionType) {
    this.intf = _MCUInterface(memorySizeOverride: intf.memorySizeOverride)
      ..connectIO(this, intf,
          inputTags: {_MCUInterfaceTag.input},
          outputTags: {_MCUInterfaceTag.output});

    _buildLogic();
  }

  void _buildLogic() {
    final mcu = _MCUInterface(memorySizeOverride: intf.memorySizeOverride);
    _MemoryControllerUnit(mcu);

    switch (_combConnectionType) {
      case ManySeqAndCombCombConnectionType.assignments:
        mcu.clock <= intf.clock;
        mcu.enable <= intf.enable;
        mcu.write <= intf.write;
        mcu.selectByte <= intf.selectByte;
        mcu.address <= intf.address;
        mcu.inputData <= intf.inputData;
        intf.outputData <= mcu.outputData;
        break;
      case ManySeqAndCombCombConnectionType.manyCombs:
        Combinational([mcu.clock < intf.clock]);
        Combinational([mcu.enable < intf.enable]);
        Combinational([mcu.write < intf.write]);
        Combinational([mcu.selectByte < intf.selectByte]);
        Combinational([mcu.address < intf.address]);
        Combinational([mcu.inputData < intf.inputData]);
        Combinational([intf.outputData < mcu.outputData]);
        break;
      case ManySeqAndCombCombConnectionType.oneComb:
        Combinational([
          mcu.clock < intf.clock,
          mcu.enable < intf.enable,
          mcu.write < intf.write,
          mcu.selectByte < intf.selectByte,
          mcu.address < intf.address,
          mcu.inputData < intf.inputData,
          intf.outputData < mcu.outputData,
        ]);
        break;
      case ManySeqAndCombCombConnectionType.manySsaCombs:
        Combinational.ssa((s) => [mcu.clock < intf.clock]);
        Combinational.ssa((s) => [mcu.enable < intf.enable]);
        Combinational.ssa((s) => [mcu.write < intf.write]);
        Combinational.ssa((s) => [mcu.selectByte < intf.selectByte]);
        Combinational.ssa((s) => [mcu.address < intf.address]);
        Combinational.ssa((s) => [mcu.inputData < intf.inputData]);
        Combinational.ssa((s) => [intf.outputData < mcu.outputData]);
        break;
      case ManySeqAndCombCombConnectionType.oneSsaComb:
        Combinational.ssa((s) => [
              mcu.clock < intf.clock,
              mcu.enable < intf.enable,
              mcu.write < intf.write,
              mcu.selectByte < intf.selectByte,
              mcu.address < intf.address,
              mcu.inputData < intf.inputData,
              intf.outputData < mcu.outputData,
            ]);
        break;
    }
  }
}

class ManySeqAndCombBenchmark extends AsyncBenchmarkBase {
  final ManySeqAndCombCombConnectionType combConnectionType;

  ManySeqAndCombBenchmark(this.combConnectionType)
      : super('ManySeqAndCombBenchmark_${combConnectionType.name}');

  @override
  Future<void> run() async {
    final combinationalWrapper = _CombinationalWrapper(
      _MCUInterface(memorySizeOverride: 1024),
      combConnectionType,
    );
    await combinationalWrapper.build();
  }
}

Future<void> main() async {
  await ManySeqAndCombBenchmark(ManySeqAndCombCombConnectionType.assignments)
      .report();
  await ManySeqAndCombBenchmark(ManySeqAndCombCombConnectionType.oneComb)
      .report();
  await ManySeqAndCombBenchmark(ManySeqAndCombCombConnectionType.manyCombs)
      .report();
  await ManySeqAndCombBenchmark(ManySeqAndCombCombConnectionType.oneSsaComb)
      .report();
  await ManySeqAndCombBenchmark(ManySeqAndCombCombConnectionType.manySsaCombs)
      .report();
}

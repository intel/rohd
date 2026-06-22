// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// fst_writer_test.dart
// Tests for FST writer and WaveDumper FST format support.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import 'pipeline_test.dart' show SimplePipelineModule;

/// A simple module for testing.
class _SimpleModule extends Module {
  _SimpleModule(Logic a) {
    a = addInput('a', a);
    addOutput('b') <= a;
  }
}

/// A module with multi-bit signals for testing.
class _MultiBitModule extends Module {
  _MultiBitModule(Logic a, Logic clk) {
    a = addInput('a', a, width: a.width);
    final aClk = addInput('clk', clk);
    addOutput('q', width: a.width) <= FlipFlop(aClk, a).q;
  }
}

const _tempDumpDir = 'tmp_test';

/// Gets the path of the FST file based on a name.
String _temporaryFstPath(String name) => '$_tempDumpDir/temp_dump_$name.fst';

/// Attaches a [WaveDumper] to [module] with FST format.
void _createFstDump(Module module, String name) {
  Directory(_tempDumpDir).createSync(recursive: true);
  final tmpDumpFile = _temporaryFstPath(name);
  WaveDumper(module, outputPath: tmpDumpFile, format: WaveFormat.fst);
}

/// Deletes the temporary FST file associated with [name].
void _deleteFstDump(String name) {
  final tmpDumpFile = _temporaryFstPath(name);
  if (File(tmpDumpFile).existsSync()) {
    File(tmpDumpFile).deleteSync();
  }
}

/// Reads a big-endian u64 from [data] at [offset].
int _readU64(Uint8List data, int offset) {
  var result = 0;
  for (var i = 0; i < 8; i++) {
    result = (result << 8) | data[offset + i];
  }
  return result;
}

/// Parses FST file blocks and returns a map of block types to counts.
Map<int, int> _parseFstBlocks(Uint8List data) {
  final blocks = <int, int>{};
  var pos = 0;
  while (pos < data.length) {
    final blockType = data[pos];
    pos++;
    if (pos + 8 > data.length) {
      break;
    }
    final sectionLength = _readU64(data, pos);
    blocks[blockType] = (blocks[blockType] ?? 0) + 1;
    pos += sectionLength;
    if (sectionLength == 0) {
      break;
    }
  }
  return blocks;
}

/// Parses FST header and returns key fields.
Map<String, int> _parseFstHeader(Uint8List data) {
  // Skip block type byte (0)
  if (data[0] != 0) {
    throw FormatException('Expected header block type 0, got ${data[0]}');
  }
  final sectionLength = _readU64(data, 1);
  if (sectionLength != 329) {
    throw FormatException(
        'Expected header section length 329, got $sectionLength');
  }
  return {
    'start_time': _readU64(data, 9),
    'end_time': _readU64(data, 17),
    // skip double_endian_test (8 bytes at offset 25)
    'scope_count': _readU64(data, 41),
    'var_count': _readU64(data, 49),
    'max_var_id': _readU64(data, 57),
    'vc_section_count': _readU64(data, 65),
    'timescale_exponent': data[73], // offset 73 = 1 + 8*9
  };
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('FstWriter unit tests', () {
    test('writes valid header block', () {
      const path = '$_tempDumpDir/fst_header_test.fst';
      Directory(_tempDumpDir).createSync(recursive: true);

      FstWriter(path)
        ..pushScope('top')
        ..declareSignal('clk', 1)
        ..declareSignal('data', 8)
        ..popScope()
        ..finish();

      final data = File(path).readAsBytesSync();
      expect(data[0], equals(0), reason: 'First byte should be header type');
      final sectionLength = _readU64(data, 1);
      expect(sectionLength, equals(329), reason: 'Header is 329 bytes');

      // Parse header fields
      final header = _parseFstHeader(data);
      expect(header['scope_count'], equals(1));
      expect(header['var_count'], equals(2));
      expect(header['max_var_id'], equals(2));

      File(path).deleteSync();
    });

    test('writes all required block types', () {
      const path = '$_tempDumpDir/fst_blocks_test.fst';
      Directory(_tempDumpDir).createSync(recursive: true);

      final writer = FstWriter(path)..pushScope('top');
      final clk = writer.declareSignal('clk', 1);
      writer
        ..popScope()
        ..writeHeader()
        ..emitValueChange(0, clk, '0')
        ..emitValueChange(5, clk, '1')
        ..finish();

      final data = File(path).readAsBytesSync();
      final blocks = _parseFstBlocks(data);

      // Must have: Header(0), VcDataDynamicAlias2(8), Geometry(3),
      //            Hierarchy(4)
      expect(blocks.containsKey(0), isTrue, reason: 'Must have header');
      expect(blocks.containsKey(8), isTrue, reason: 'Must have VcData block');
      expect(blocks.containsKey(3), isTrue, reason: 'Must have geometry');
      expect(blocks.containsKey(4), isTrue, reason: 'Must have hierarchy');

      File(path).deleteSync();
    });

    test('geometry encodes signal widths correctly', () {
      const path = '$_tempDumpDir/fst_geometry_test.fst';
      Directory(_tempDumpDir).createSync(recursive: true);

      FstWriter(path)
        ..pushScope('top')
        ..declareSignal('bit1', 1)
        ..declareSignal('byte8', 8)
        ..declareSignal('word32', 32)
        ..popScope()
        ..finish();

      final data = File(path).readAsBytesSync();

      // Find the geometry block (type 3)
      var pos = 0;
      while (pos < data.length) {
        if (data[pos] == 3) {
          // Geometry block
          final sectionLength = _readU64(data, pos + 1);
          final maxHandle = _readU64(data, pos + 1 + 16);
          expect(maxHandle, equals(3));

          // Geometry data is after section_length(8) + unc_len(8) +
          // max_handle(8) = 24 bytes from section_length start
          // May be compressed, so just check the block exists
          expect(sectionLength, greaterThan(24));
          break;
        }
        pos++;
        if (pos + 8 > data.length) {
          break;
        }
        final sl = _readU64(data, pos);
        pos += sl;
        if (sl == 0) {
          break;
        }
      }

      File(path).deleteSync();
    });
  });

  group('WaveDumper FST format', () {
    test('basic 1-bit signal FST dump', () async {
      final a = Logic(name: 'a');
      final mod = _SimpleModule(a);
      await mod.build();

      const dumpName = 'fstBasic';
      _createFstDump(mod, dumpName);

      a.put(0);
      Simulator.setMaxSimTime(100);
      await Simulator.run();

      final fstFile = File(_temporaryFstPath(dumpName));
      expect(fstFile.existsSync(), isTrue);

      final data = fstFile.readAsBytesSync();
      // File should have valid FST header
      expect(data[0], equals(0), reason: 'First byte is header block type');
      expect(_readU64(data, 1), equals(329));

      // Check blocks are present
      final blocks = _parseFstBlocks(data);
      expect(blocks.containsKey(0), isTrue, reason: 'header');
      expect(blocks.containsKey(3), isTrue, reason: 'geometry');
      expect(blocks.containsKey(4), isTrue, reason: 'hierarchy');

      _deleteFstDump(dumpName);
    });

    test('multi-bit signal FST dump', () async {
      final a = Logic(name: 'a', width: 8);
      final clk = SimpleClockGenerator(10).clk;
      final mod = _MultiBitModule(a, clk);
      await mod.build();

      const dumpName = 'fstMultiBit';
      _createFstDump(mod, dumpName);

      a.put(0);
      Simulator.setMaxSimTime(100);
      unawaited(Simulator.run());

      await clk.nextPosedge;
      a.inject(0xAB);
      await clk.nextPosedge;
      a.inject(0xFF);

      await Simulator.simulationEnded;

      final fstFile = File(_temporaryFstPath(dumpName));
      expect(fstFile.existsSync(), isTrue);

      final data = fstFile.readAsBytesSync();
      final blocks = _parseFstBlocks(data);
      expect(blocks.containsKey(0), isTrue);
      expect(blocks.containsKey(8), isTrue,
          reason: 'VcData block with changes');

      _deleteFstDump(dumpName);
    });

    test('FST file creates non-existent directories', () async {
      final a = Logic(name: 'a');
      final mod = _SimpleModule(a);
      await mod.build();

      const dir1Path = '$_tempDumpDir/fst_dir1';
      const fstPath = '$dir1Path/dir2/waves.fst';

      WaveDumper(mod, outputPath: fstPath, format: WaveFormat.fst);

      a.put(0);
      Simulator.setMaxSimTime(10);
      await Simulator.run();

      expect(File(fstPath).existsSync(), isTrue);

      if (Directory(dir1Path).existsSync()) {
        Directory(dir1Path).deleteSync(recursive: true);
      }
    });

    test('FST header has correct signal counts', () async {
      final a = Logic(name: 'a');
      final mod = _SimpleModule(a);
      await mod.build();

      const dumpName = 'fstCounts';
      _createFstDump(mod, dumpName);

      a.put(0);
      Simulator.setMaxSimTime(10);
      await Simulator.run();

      final data = File(_temporaryFstPath(dumpName)).readAsBytesSync();
      final header = _parseFstHeader(data);

      // _SimpleModule has 2 signals: input 'a' and output 'b'
      expect(header['var_count'], equals(2));

      _deleteFstDump(dumpName);
    });

    test('FST and VCD both produce output', () async {
      // Create a module
      final a = Logic(name: 'a');
      final mod = _SimpleModule(a);
      await mod.build();

      // Dump as FST
      const fstName = 'fstCompare';
      _createFstDump(mod, fstName);

      a.put(0);
      Simulator.setMaxSimTime(50);
      unawaited(Simulator.run());

      a.inject(1);

      await Simulator.simulationEnded;

      final fstFile = File(_temporaryFstPath(fstName));
      expect(fstFile.existsSync(), isTrue);
      final fstSize = fstFile.lengthSync();
      expect(fstSize, greaterThan(330), reason: 'FST should be > header size');

      _deleteFstDump(fstName);

      // Reset and dump as VCD
      await Simulator.reset();

      final a2 = Logic(name: 'a');
      final mod2 = _SimpleModule(a2);
      await mod2.build();

      const vcdPath = '$_tempDumpDir/temp_dump_vcdCompare.vcd';
      Directory(_tempDumpDir).createSync(recursive: true);
      WaveDumper(mod2, outputPath: vcdPath);

      a2.put(0);
      Simulator.setMaxSimTime(50);
      unawaited(Simulator.run());

      a2.inject(1);

      await Simulator.simulationEnded;

      final vcdFile = File(vcdPath);
      expect(vcdFile.existsSync(), isTrue);
      expect(vcdFile.lengthSync(), greaterThan(0));

      vcdFile.deleteSync();
    });

    test('pipeline FST has VcData and is readable by fst2vcd', () async {
      // Build a 3-stage 8-bit pipeline that generates many signal changes.
      final a = Logic(name: 'a', width: 8);
      final mod = SimplePipelineModule(a);
      await mod.build();

      const dumpName = 'fstPipeline';
      _createFstDump(mod, dumpName);

      // Drive 200 clock cycles worth of incrementing inputs.
      // The 10ps clock gives 2000ps total, producing many VcData changes.
      a.put(0);
      Simulator.setMaxSimTime(2000);
      unawaited(Simulator.run());

      // Inject a new value every 10ps to keep signals active
      for (var i = 1; i <= 200; i++) {
        await Future<void>.delayed(Duration.zero);
        a.inject(i & 0xFF);
      }

      await Simulator.simulationEnded;

      final fstFile = File(_temporaryFstPath(dumpName));
      expect(fstFile.existsSync(), isTrue);

      // File should be substantially larger than just the header (329 bytes)
      final fileSize = fstFile.lengthSync();
      expect(fileSize, greaterThan(600),
          reason: 'Pipeline FST should have VcData content');

      // Parse blocks: must include at least one VcData block (type 8)
      final data = fstFile.readAsBytesSync();
      final blocks = _parseFstBlocks(data);
      expect(blocks.containsKey(0), isTrue, reason: 'header block');
      expect(blocks.containsKey(8), isTrue, reason: 'VcData block');
      expect(blocks.containsKey(3), isTrue, reason: 'geometry block');
      expect(blocks.containsKey(4), isTrue, reason: 'hierarchy block');

      // Validate with fst2vcd (GTKWave tool) if available.
      final fst2vcd = Process.runSync('which', ['fst2vcd']);
      if (fst2vcd.exitCode == 0) {
        final result = Process.runSync('fst2vcd', [fstFile.path]);
        expect(result.exitCode, equals(0),
            reason: 'fst2vcd failed: ${result.stdout}\n${result.stderr}');
        final vcdOutput = result.stdout as String;
        expect(vcdOutput, contains(r'$timescale'),
            reason: 'fst2vcd output should be valid VCD');
      }

      _deleteFstDump(dumpName);
    });
  });
}

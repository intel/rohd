// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_service_test.dart
// Tests for WaveformService output and VCD/FST event parity.
//
// 2026 July 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/vcd_parser.dart';
import 'package:test/test.dart';

class _SimpleWaveModule extends Module {
  _SimpleWaveModule(Logic a) {
    a = addInput('a', a, width: a.width);
    addOutput('b', width: a.width) <= ~a;
  }
}

const _tempDumpDir = 'tmp_test';

String _temporaryVcdPath(String name) => '$_tempDumpDir/temp_wave_$name.vcd';

String _temporaryFstPath(String name) => '$_tempDumpDir/temp_wave_$name.fst';

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('registers with ModuleServices by default', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    WaveformService(mod);

    final service = ModuleServices.instance.lookup<WaveformService>();
    expect(service, isNotNull);
    final waveformJson = jsonEncode(service!.toJson());
    expect(waveformJson, contains('"format":"vcd"'));
  });

  test('captures waveform to VCD output path', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryVcdPath('serviceCapture');

    WaveformService(mod, outputPath: dumpPath, register: false);

    a.inject(1);
    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final vcdContents = File(dumpPath).readAsStringSync();
    expect(
      VcdParser.confirmValue(vcdContents, 'a', 0, LogicValue.ofString('1')),
      equals(true),
    );
    expect(
      VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
      equals(true),
    );

    File(dumpPath).deleteSync();
  });

  test('captures waveform to FST format', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryFstPath('fstCapture');

    WaveformService(
      mod,
      outputPath: dumpPath,
      format: WaveOutputFormat.fst,
      register: false,
    );

    a.inject(1);
    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final fstFile = File(dumpPath);
    expect(fstFile.existsSync(), isTrue);
    expect(fstFile.lengthSync(), greaterThan(100));

    fstFile.deleteSync();
  });

  test('VCD and FST contain matching value-change events', () async {
    final vcdPath = _temporaryVcdPath('parity');
    final fstPath = _temporaryFstPath('parity');

    await _dumpParityWaveform(vcdPath, WaveOutputFormat.vcd);
    final vcdEvents = _readVcdEvents(vcdPath, const {'a', 'b'});

    await Simulator.reset();
    ModuleServices.instance.reset();

    await _dumpParityWaveform(fstPath, WaveOutputFormat.fst);
    final fstEvents = _readFstEvents(
      fstPath,
      signalNames: const ['a', 'b'],
      signalWidths: const [4, 4],
    );

    expect(fstEvents, equals(vcdEvents));

    File(vcdPath).deleteSync();
    File(fstPath).deleteSync();
  });
}

Future<void> _dumpParityWaveform(
    String outputPath, WaveOutputFormat format) async {
  Directory(_tempDumpDir).createSync(recursive: true);

  final a = Logic(name: 'a', width: 4);
  final mod = _SimpleWaveModule(a);
  await mod.build();

  a.put(0x1);
  WaveformService(
    mod,
    outputPath: outputPath,
    format: format,
    register: false,
  );

  Simulator.registerAction(10, () => a.put(0x2));
  Simulator.registerAction(20, () => a.put(0xf));
  await Simulator.run();
}

Map<String, Map<int, String>> _readVcdEvents(
  String path,
  Set<String> signalNames,
) {
  final lines = File(path).readAsLinesSync();
  final markerToSignal = <String, String>{};
  final markerToWidth = <String, int>{};
  final events = <String, Map<int, String>>{
    for (final name in signalNames) name: <int, String>{},
  };

  final sigNameRegexp = RegExp(
    r'\s*\$var\s(wire|reg)\s(\d+)\s(\S*)\s(\S*)\s+(\[\d+\:\d+\])?\s*\$end',
  );
  var currentTime = 0;
  var inValues = false;

  for (final line in lines) {
    final match = sigNameRegexp.firstMatch(line);
    if (match != null) {
      final width = int.parse(match.group(2)!);
      final marker = match.group(3)!;
      final name = match.group(4)!;
      if (signalNames.contains(name)) {
        markerToSignal[marker] = name;
        markerToWidth[marker] = width;
      }
      continue;
    }

    if (line == r'$dumpvars') {
      inValues = true;
      continue;
    }
    if (!inValues) {
      continue;
    }
    if (line == r'$end') {
      continue;
    }
    if (line.startsWith('#')) {
      currentTime = int.parse(line.substring(1));
      continue;
    }

    final parsed = _parseVcdValueUpdate(line, markerToWidth);
    if (parsed == null) {
      continue;
    }

    final signalName = markerToSignal[parsed.marker];
    if (signalName != null) {
      events[signalName]![currentTime] = parsed.value;
    }
  }

  return events;
}

({String marker, String value})? _parseVcdValueUpdate(
  String line,
  Map<String, int> markerToWidth,
) {
  if (line.startsWith('b')) {
    final parts = line.split(' ');
    if (parts.length != 2 || !markerToWidth.containsKey(parts[1])) {
      return null;
    }
    return (marker: parts[1], value: parts[0].substring(1));
  }

  for (final marker in markerToWidth.keys) {
    if (line.endsWith(marker)) {
      return (marker: marker, value: line[0]);
    }
  }
  return null;
}

Map<String, Map<int, String>> _readFstEvents(
  String path, {
  required List<String> signalNames,
  required List<int> signalWidths,
}) {
  final data = File(path).readAsBytesSync();
  final events = <String, Map<int, String>>{
    for (final name in signalNames) name: <int, String>{},
  };

  var blockOffset = 0;
  while (blockOffset < data.length) {
    final blockType = data[blockOffset];
    final sectionLength = _readU64(data, blockOffset + 1);
    final blockEnd = blockOffset + 1 + sectionLength;

    if (blockType == 8) {
      _readFstVcDataBlock(
        data,
        blockOffset,
        blockEnd,
        signalNames: signalNames,
        signalWidths: signalWidths,
        events: events,
      );
    }

    blockOffset = blockEnd;
  }

  return events;
}

void _readFstVcDataBlock(
  Uint8List data,
  int blockOffset,
  int blockEnd, {
  required List<String> signalNames,
  required List<int> signalWidths,
  required Map<String, Map<int, String>> events,
}) {
  final startTime = _readU64(data, blockOffset + 9);
  var offset = blockOffset + 33;

  final frameUncompressed = _readVarint(data, offset);
  offset = frameUncompressed.next;
  final frameCompressed = _readVarint(data, offset);
  offset = frameCompressed.next;
  final maxHandle = _readVarint(data, offset);
  offset = maxHandle.next;

  final frameBytes = _inflateIfNeeded(
    data.sublist(offset, offset + frameCompressed.value),
    frameUncompressed.value,
  );
  offset += frameCompressed.value;

  var frameOffset = 0;
  for (var i = 0; i < signalNames.length; i++) {
    final width = signalWidths[i];
    final value = String.fromCharCodes(
        frameBytes.sublist(frameOffset, frameOffset + width));
    frameOffset += width;
    events[signalNames[i]]![startTime] = value;
  }

  final valueMaxHandle = _readVarint(data, offset);
  offset = valueMaxHandle.next;
  final valueSectionStart = offset;
  offset++; // pack_type

  final timeCount = _readU64(data, blockEnd - 8);
  final timeCompressedLength = _readU64(data, blockEnd - 16);
  final timeUncompressedLength = _readU64(data, blockEnd - 24);
  final timeDataStart = blockEnd - 24 - timeCompressedLength;
  final timeBytes = _inflateIfNeeded(
    data.sublist(timeDataStart, timeDataStart + timeCompressedLength),
    timeUncompressedLength,
  );
  final timeTable = _decodeTimeTable(timeBytes, timeCount);

  final chainLength = _readU64(data, timeDataStart - 8);
  final chainStart = timeDataStart - 8 - chainLength;
  final signalOffsets = _decodeFstOffsetChain(
    data.sublist(chainStart, timeDataStart - 8),
    valueMaxHandle.value,
  );

  for (var signalIndex = 0; signalIndex < signalNames.length; signalIndex++) {
    final signalOffset = signalOffsets[signalIndex];
    if (signalOffset == null) {
      continue;
    }

    final nextOffset = signalOffsets
        .skip(signalIndex + 1)
        .whereType<int>()
        .cast<int?>()
        .firstWhere((offset) => offset != null, orElse: () => null);
    final signalDataStart = valueSectionStart + signalOffset;
    final signalDataEnd =
        nextOffset == null ? chainStart : valueSectionStart + nextOffset;
    _decodeFstSignalData(
      data.sublist(signalDataStart, signalDataEnd),
      width: signalWidths[signalIndex],
      signalName: signalNames[signalIndex],
      timeTable: timeTable,
      events: events,
    );
  }
}

List<int> _decodeTimeTable(Uint8List bytes, int count) {
  final times = <int>[];
  var offset = 0;
  var previousTime = 0;
  for (var i = 0; i < count; i++) {
    final delta = _readVarint(bytes, offset);
    offset = delta.next;
    previousTime += delta.value;
    times.add(previousTime);
  }
  return times;
}

List<int?> _decodeFstOffsetChain(Uint8List bytes, int maxHandle) {
  final offsets = List<int?>.filled(maxHandle, null);
  var byteOffset = 0;
  var signalIndex = 0;
  var previousOffset = 0;

  while (signalIndex < maxHandle && byteOffset < bytes.length) {
    final encoded = _readSignedVarint(bytes, byteOffset);
    byteOffset = encoded.next;
    if (encoded.value.isEven) {
      signalIndex += encoded.value >> 1;
    } else {
      previousOffset += encoded.value >> 1;
      offsets[signalIndex] = previousOffset;
      signalIndex++;
    }
  }

  return offsets;
}

void _decodeFstSignalData(
  Uint8List bytes, {
  required int width,
  required String signalName,
  required List<int> timeTable,
  required Map<String, Map<int, String>> events,
}) {
  var offset = 0;
  final compression = _readVarint(bytes, offset);
  offset = compression.next;
  expect(compression.value, equals(0),
      reason: 'Only uncompressed signal chains are expected');

  var timeIndex = 0;
  while (offset < bytes.length) {
    if (width == 1) {
      final encoded = _readVarint(bytes, offset);
      offset = encoded.next;
      String value;
      int timeDelta;
      if (encoded.value.isEven) {
        value = ((encoded.value >> 1) & 1).toString();
        timeDelta = encoded.value >> 2;
      } else {
        const rcvChars = 'xzhuwl-?';
        value = rcvChars[(encoded.value >> 1) & 0x7];
        timeDelta = encoded.value >> 4;
      }
      timeIndex += timeDelta;
      events[signalName]![timeTable[timeIndex]] = value;
    } else {
      final encoded = _readVarint(bytes, offset);
      offset = encoded.next;
      timeIndex += encoded.value >> 1;

      final isFourState = encoded.value.isOdd;
      String value;
      if (isFourState) {
        value = String.fromCharCodes(bytes.sublist(offset, offset + width));
        offset += width;
      } else {
        final byteCount = (width + 7) ~/ 8;
        final packed = bytes.sublist(offset, offset + byteCount);
        offset += byteCount;
        value = _unpackTwoStateBits(packed, width);
      }

      events[signalName]![timeTable[timeIndex]] = value;
    }
  }
}

String _unpackTwoStateBits(Uint8List bytes, int width) {
  final bits = StringBuffer();
  for (var i = 0; i < width; i++) {
    final byteIndex = i ~/ 8;
    final bitIndex = 7 - (i % 8);
    bits.write(((bytes[byteIndex] >> bitIndex) & 1).toString());
  }
  return bits.toString();
}

Uint8List _inflateIfNeeded(Uint8List bytes, int uncompressedLength) {
  if (bytes.length == uncompressedLength) {
    return bytes;
  }
  return Uint8List.fromList(ZLibCodec().decode(bytes));
}

({int value, int next}) _readVarint(Uint8List data, int offset) {
  var value = 0;
  var shift = 0;
  var next = offset;

  while (true) {
    final byte = data[next++];
    value |= (byte & 0x7f) << shift;
    if ((byte & 0x80) == 0) {
      return (value: value, next: next);
    }
    shift += 7;
  }
}

({int value, int next}) _readSignedVarint(Uint8List data, int offset) {
  var value = 0;
  var shift = 0;
  var next = offset;
  late int byte;

  do {
    byte = data[next++];
    value |= (byte & 0x7f) << shift;
    shift += 7;
  } while ((byte & 0x80) != 0);

  if (shift < 64 && (byte & 0x40) != 0) {
    value |= -(1 << shift);
  }

  return (value: value, next: next);
}

int _readU64(Uint8List data, int offset) {
  var result = 0;
  for (var i = 0; i < 8; i++) {
    result = (result << 8) | data[offset + i];
  }
  return result;
}

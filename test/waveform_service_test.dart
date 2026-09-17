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

class _WindowWaveModule extends Module {
  late final Logic a;

  _WindowWaveModule() {
    a = addOutput('a');
  }
}

class _FanoutWaveModule extends Module {
  _FanoutWaveModule(Logic a) {
    a = addInput('a', a, width: a.width);
    for (var i = 0; i < 16; i++) {
      addOutput('out$i', width: a.width) <= a;
    }
  }
}

class _LiveFstQueryWaveformService extends WaveformService {
  Map<String, List<(int, String)>>? liveValuesAtWindowEntry;

  _LiveFstQueryWaveformService(super.module, {required String outputPath})
      : super(
          outputDirectory: Directory(outputPath).parent.path,
          outputFileName: File(outputPath).uri.pathSegments.last,
          format: WaveOutputFormat.fst,
          startTime: 10,
          register: false,
          writeToFile: true,
        );

  @override
  void onTimestampCapture(int timestamp, Set<Logic> changed) {
    if (timestamp != 10) {
      return;
    }
    final query = createWaveformQuery();
    liveValuesAtWindowEntry = {
      for (final signal in query.signals)
        signal.name: [
          for (final change in query.changes(
            signal,
            startTime: 10,
            endTime: 10,
          ))
            (change.time, change.value),
        ],
    };
  }
}

class _HistoryWaveformService extends WaveformService {
  final Map<Logic, List<(int, String)>> history = {};
  final List<int> capturedTimestamps = [];

  _HistoryWaveformService(super.module, {super.startTime, super.register});

  @override
  void onSignalCollected(Logic signal) {
    history[signal] = [(Simulator.time, _binaryValue(signal))];
  }

  @override
  void onValueChange(Logic signal, int timestamp) {
    history[signal]!.add((timestamp, _binaryValue(signal)));
  }

  @override
  void onTimestampCapture(int timestamp, Set<Logic> changed) {
    capturedTimestamps.add(timestamp);
  }
}

String _binaryValue(Logic signal) => signal.value.reversed
    .toList()
    .map((value) => value.toString(includeWidth: false))
    .join();

const _tempDumpDir = 'tmp_test';

String _temporaryVcdPath(String name) => '$_tempDumpDir/temp_wave_$name.vcd';

String _temporaryFstPath(String name) => '$_tempDumpDir/temp_wave_$name.fst';

int _readFstTimescaleExponent(Uint8List data) {
  const timescaleExponentOffset = 73;
  final unsignedExponent = data[timescaleExponentOffset];
  return unsignedExponent < 0x80 ? unsignedExponent : unsignedExponent - 0x100;
}

// ─── Public helpers used by sibling tests (e.g. config_test.dart) ────────────

/// Directory into which sibling tests place their temporary waveform dumps.
const tempDumpDir = 'tmp_test';

/// Gets the path of the VCD file based on a name.
String temporaryDumpPath(String name) => '$tempDumpDir/temp_dump_$name.vcd';

/// Attaches a [WaveformService] to [module] to VCD with [name].
void createTemporaryDump(Module module, String name) {
  Directory(tempDumpDir).createSync(recursive: true);
  WaveformService(
    module,
    outputDirectory: tempDumpDir,
    outputBaseName: 'temp_dump_$name',
    writeToFile: true,
  );
}

/// Deletes the VCD file previously created by [createTemporaryDump].
void deleteTemporaryDump(String name) {
  final tmpDumpFile = temporaryDumpPath(name);
  File(tmpDumpFile).deleteSync();
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
    WaveformDataService.instance.clear();
  });

  test('file-backed debugging capture can retain history', () async {
    final mod = _SimpleWaveModule(Logic());
    await mod.build();

    final service = WaveformService(
      mod,
      outputDirectory: tempDumpDir,
      outputBaseName: 'temp_dump_debugDump',
      writeToFile: true,
      retainInMemory: true,
    );

    expect(service.retainInMemory, isTrue);
    expect(service.canSendWaveforms(), isTrue);
    expect(service.inMemoryOutput, isNotNull);

    await Simulator.run();
    deleteTemporaryDump('debugDump');
  });

  test('registers with ModuleServices by default', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryVcdPath('serviceRegistration');

    WaveformService.fromOutputPath(mod, outputPath: dumpPath);

    final service = ModuleServices.instance.lookup<WaveformService>();
    expect(service, isNotNull);
    final waveformJson = jsonEncode(service!.toJson());
    expect(waveformJson, contains('"format":"vcd"'));

    File(dumpPath).deleteSync();
  });

  test('window-entry snapshot reaches waveform hooks', () async {
    final mod = _WindowWaveModule();
    await mod.build();
    mod.a.put(0);

    final service =
        _HistoryWaveformService(mod, startTime: 10, register: false);

    Simulator.registerAction(5, () => mod.a.put(1));
    Simulator.registerAction(15, () {});
    Simulator.registerAction(20, () {});
    await Simulator.run();

    final vcdContents = utf8.decode(
      await service.artifacts.single
          .openRead()
          .expand((bytes) => bytes)
          .toList(),
    );
    expect(
      VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.one),
      isTrue,
    );
    expect(service.history[mod.a], equals([(0, '0'), (10, '1')]));
    expect(service.capturedTimestamps, contains(10));
  });

  test('window entry and boundary change are separate hook batches', () async {
    final mod = _WindowWaveModule();
    await mod.build();
    mod.a.put(0);
    final service =
        _HistoryWaveformService(mod, startTime: 10, register: false);

    Simulator.registerAction(5, () => mod.a.put(1));
    Simulator.registerAction(10, () => mod.a.put(0));
    await Simulator.run();

    expect(
      service.history[mod.a],
      equals([(0, '0'), (10, '1'), (10, '0')]),
    );
    expect(service.capturedTimestamps, equals([10, 10]));
  });

  test('window-entry FST values agree live, finalized, and in fst2vcd',
      () async {
    final a = Logic(name: 'a', width: 8);
    final mod = _FanoutWaveModule(a);
    await mod.build();
    a.put(0);

    Directory(_tempDumpDir).createSync(recursive: true);
    final fstPath = _temporaryFstPath('windowEntrySameTimestamp');
    final fstFile = File(fstPath);
    addTearDown(() {
      if (fstFile.existsSync()) {
        fstFile.deleteSync();
      }
    });
    final service = _LiveFstQueryWaveformService(mod, outputPath: fstPath);

    Simulator.registerAction(5, () => a.put(1));
    Simulator.registerAction(10, () => a.put(0));
    Simulator.registerAction(20, () => a.put(1));
    await Simulator.run();

    final query = service.createWaveformQuery();
    final finalizedValues = {
      for (final signal in query.signals)
        signal.name: [
          for (final change in query.changes(
            signal,
            startTime: 10,
            endTime: 10,
          ))
            (change.time, change.value),
        ],
    };
    expect(service.liveValuesAtWindowEntry, isNotNull);
    expect(finalizedValues, equals(service.liveValuesAtWindowEntry));
    expect(
      finalizedValues.values,
      everyElement(equals([(10, '00000000')])),
    );

    if (Process.runSync('which', ['fst2vcd']).exitCode == 0) {
      final conversion = Process.runSync('fst2vcd', [fstPath]);
      expect(
        conversion.exitCode,
        equals(0),
        reason: 'fst2vcd failed: ${conversion.stdout}\n${conversion.stderr}',
      );
      final vcdContents = conversion.stdout as String;
      for (final name in finalizedValues.keys) {
        expect(
          VcdParser.confirmValue(
            vcdContents,
            name,
            10,
            LogicValue.ofString('00000000'),
          ),
          isTrue,
          reason: '$name should be zero at the window-entry timestamp',
        );
      }
    }
  });

  test('captures waveform to VCD output path', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryVcdPath('serviceCapture');

    final service = WaveformService.fromOutputPath(
      mod,
      outputPath: dumpPath,
      register: false,
      enableDevToolsStreaming: true,
    );
    expect(service.outputFilePath, dumpPath);

    a.inject(1);
    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final vcdContents = File(dumpPath).readAsStringSync();
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 0, LogicValue.ofString('1')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
        equals(true));

    File(dumpPath).deleteSync();
  });

  test('captures waveform to FST format', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryFstPath('fstCapture');

    WaveformService.fromOutputPath(
      mod,
      outputPath: dumpPath,
      format: WaveOutputFormat.fst,
      register: false,
      enableDevToolsStreaming: true,
    );

    a.inject(1);
    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final fstFile = File(dumpPath);
    expect(fstFile.existsSync(), isTrue);
    expect(fstFile.lengthSync(), greaterThan(100));

    fstFile.deleteSync();
  });

  test('FST writer tuning uses the backend-specific constructor', () async {
    final mod = _SimpleWaveModule(Logic(name: 'a'));
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final fstFile = File(_temporaryFstPath('fstWriterConfig'));
    addTearDown(() {
      if (fstFile.existsSync()) {
        fstFile.deleteSync();
      }
    });
    final service = WaveformService.fst(
      mod,
      outputDirectory: _tempDumpDir,
      outputBaseName: 'temp_wave_fstWriterConfig',
      register: false,
      config: const FstWriterConfig(maxChangesPerBlock: 2),
    );

    await Simulator.run();

    final writerMetadata = service.toJson()['writer']! as Map<String, Object?>;
    expect(writerMetadata['maxChangesPerBlock'], equals(2));
  });

  test('VCD query capability reports unsupported explicitly', () async {
    final mod = _SimpleWaveModule(Logic(name: 'a'));
    await mod.build();

    final service = WaveformService(mod, register: false);

    expect(service.createWaveformQuery, throwsUnsupportedError);
  });

  test('rejects unsupported waveform timescale exponents', () {
    expect(
      () => WaveformTimeScale.fromExponent(-16),
      throwsArgumentError,
    );
    expect(
      () => WaveformTimeScale.fromExponent(3),
      throwsArgumentError,
    );
  });

  for (final format in WaveOutputFormat.values) {
    test(
        '${format.name} preserves existing output with failIfExists and '
        'overwrites by default', () async {
      final a = Logic(name: 'a');
      final mod = _SimpleWaveModule(a);
      await mod.build();

      Directory(_tempDumpDir).createSync(recursive: true);
      final outputFile = File(
        '$_tempDumpDir/temp_wave_overwritePolicy.${format.fileExtension}',
      );
      addTearDown(() {
        if (outputFile.existsSync()) {
          outputFile.deleteSync();
        }
      });

      final originalContents = utf8.encode('existing waveform contents');
      outputFile.writeAsBytesSync(originalContents);

      expect(
        () => WaveformService.fromOutputPath(
          mod,
          outputPath: outputFile.path,
          format: format,
          overwritePolicy: OverwritePolicy.failIfExists,
          register: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(outputFile.readAsBytesSync(), equals(originalContents));

      a.put(0);
      WaveformService.fromOutputPath(
        mod,
        outputPath: outputFile.path,
        format: format,
        register: false,
      );
      await Simulator.run();

      expect(outputFile.readAsBytesSync(), isNot(equals(originalContents)));
      expect(outputFile.lengthSync(), greaterThan(originalContents.length));
    });
  }

  test('writes a shared non-default timescale to VCD and FST', () async {
    const timescale = WaveformTimeScale.oneNanosecond;
    Directory(_tempDumpDir).createSync(recursive: true);
    final vcdFile = File(_temporaryVcdPath('timescale'));
    final fstFile = File(_temporaryFstPath('timescale'));
    addTearDown(() {
      for (final outputFile in [vcdFile, fstFile]) {
        if (outputFile.existsSync()) {
          outputFile.deleteSync();
        }
      }
    });

    final vcdService = await _captureWaveformWithTimescale(
      vcdFile.path,
      WaveOutputFormat.vcd,
      timescale,
    );
    final vcdMetadata = vcdService.toJson();
    final vcdWriterMetadata = vcdMetadata['writer']! as Map<String, Object?>;
    final vcdContents = vcdFile.readAsStringSync();
    expect(vcdService.timescale, same(timescale));
    expect(vcdMetadata['timescale'], equals(timescale.vcdValue));
    expect(vcdWriterMetadata['timescale'], equals(timescale.vcdValue));
    expect(vcdContents, contains(r'$timescale 1ns $end'));
    expect(
      VcdParser.confirmValue(vcdContents, 'a', 100, LogicValue.one),
      isTrue,
    );

    await Simulator.reset();
    ModuleServices.instance.reset();

    final fstService = await _captureWaveformWithTimescale(
      fstFile.path,
      WaveOutputFormat.fst,
      timescale,
    );
    final fstMetadata = fstService.toJson();
    final fstWriterMetadata = fstMetadata['writer']! as Map<String, Object?>;
    final fstEvents = _readFstEvents(
      fstFile.path,
      signalNames: const ['a', 'b'],
      signalWidths: const [1, 1],
    );
    expect(fstService.timescale, same(timescale));
    expect(fstMetadata['timescale'], equals(timescale.vcdValue));
    expect(fstWriterMetadata['timescale'], equals(timescale.vcdValue));
    expect(
      fstWriterMetadata['maxChangesPerBlock'],
      equals(FstWriterConfig.defaultMaxChangesPerBlock),
    );
    expect(
      _readFstTimescaleExponent(fstFile.readAsBytesSync()),
      equals(timescale.exponent),
    );
    expect(fstEvents['a']![100], equals('1'));
  });

  test('FST converted to VCD preserves values and window snapshots', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();
    a.put(0);

    Directory(_tempDumpDir).createSync(recursive: true);
    final fstPath = _temporaryFstPath('convertedValues');
    WaveformService.fromOutputPath(mod,
        outputPath: fstPath,
        format: WaveOutputFormat.fst,
        startTime: 10,
        register: false);

    Simulator.registerAction(5, () => a.put(1));
    Simulator.registerAction(15, () => a.put(0));
    Simulator.registerAction(20, () {});
    await Simulator.run();

    final conversion = Process.runSync('fst2vcd', [fstPath]);
    expect(conversion.exitCode, equals(0),
        reason: 'fst2vcd failed: ${conversion.stdout}\n${conversion.stderr}');
    final vcdContents = conversion.stdout as String;
    expect(VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.one), isTrue,
        reason: 'the recording-window snapshot must retain the value at t=10');
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 15, LogicValue.zero), isTrue,
        reason: 'the later input transition must retain its timestamp');
    expect(
        VcdParser.confirmValue(vcdContents, 'b', 10, LogicValue.zero), isTrue,
        reason: 'the inverted output must match the input at the window start');
    expect(VcdParser.confirmValue(vcdContents, 'b', 15, LogicValue.one), isTrue,
        reason: 'the inverted output must match the later input transition');

    File(fstPath).deleteSync();
  },
      skip: Process.runSync('which', ['fst2vcd']).exitCode != 0
          ? 'fst2vcd is not installed'
          : false);

  test('streams VCD signal values to WaveformDataService', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryVcdPath('dataService');
    WaveformService.fromOutputPath(
      mod,
      outputPath: dumpPath,
      register: false,
      enableDevToolsStreaming: true,
    );

    a.inject(1);
    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final dataService = WaveformDataService.instance;
    final signalId = dataService.signalAddressMap.keys.firstWhere(
      (id) => id.endsWith('/a'),
    );
    final snapshot =
        jsonDecode(dataService.getSnapshotJSON(10)) as Map<String, dynamic>;
    final signals = snapshot['signals'] as Map<String, dynamic>;

    expect(dataService.isInitialized, isTrue);
    expect(dataService.isFstBacked, isFalse);
    expect(dataService.currentTime, equals(10));
    expect(signals[signalId], isNotNull);

    File(dumpPath).deleteSync();
  });

  test('queries FST values through WaveformDataService', () async {
    final a = Logic(name: 'a');
    final mod = _SimpleWaveModule(a);
    await mod.build();

    Directory(_tempDumpDir).createSync(recursive: true);
    final dumpPath = _temporaryFstPath('dataService');
    WaveformService.fromOutputPath(
      mod,
      outputPath: dumpPath,
      format: WaveOutputFormat.fst,
      register: false,
      enableDevToolsStreaming: true,
    );

    a.inject(1);
    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final dataService = WaveformDataService.instance;
    final signalId = dataService.signalAddressMap.keys.firstWhere(
      (id) => id.endsWith('/a'),
    );
    final waveform = jsonDecode(
      dataService.getWaveformsJSON(jsonEncode([signalId]), 0, 10),
    ) as List<dynamic>;
    final signalData = waveform.single as Map<String, dynamic>;

    expect(dataService.isFstBacked, isTrue);
    expect(signalData['signalId'], equals(signalId));
    expect(signalData['data'], isNotEmpty);
    File(dumpPath).deleteSync();
  });

  test('VCD and FST contain matching value-change events', () async {
    final vcdPath = _temporaryVcdPath('parity');
    final fstPath = _temporaryFstPath('parity');

    await _dumpParityWaveform(vcdPath, WaveOutputFormat.vcd);
    final vcdEvents = _readVcdEvents(vcdPath, const {'a', 'b'});

    await Simulator.reset();
    ModuleServices.instance.reset();

    await _dumpParityWaveform(fstPath, WaveOutputFormat.fst);
    final fstEvents = _readFstEvents(fstPath,
        signalNames: const ['a', 'b'], signalWidths: const [4, 4]);

    expect(fstEvents, equals(vcdEvents));

    File(vcdPath).deleteSync();
    File(fstPath).deleteSync();
  });
}

Future<WaveformService> _captureWaveformWithTimescale(
  String outputPath,
  WaveOutputFormat format,
  WaveformTimeScale timescale,
) async {
  final a = Logic(name: 'a');
  final mod = _SimpleWaveModule(a);
  await mod.build();
  a.put(0);

  final service = WaveformService.fromOutputPath(
    mod,
    outputPath: outputPath,
    format: format,
    timescale: timescale,
    register: false,
  );
  Simulator.registerAction(100, () => a.put(1));
  await Simulator.run();
  return service;
}

Future<void> _dumpParityWaveform(
    String outputPath, WaveOutputFormat format) async {
  Directory(_tempDumpDir).createSync(recursive: true);

  final a = Logic(name: 'a', width: 4);
  final mod = _SimpleWaveModule(a);
  await mod.build();

  a.put(0x1);
  WaveformService.fromOutputPath(mod,
      outputPath: outputPath, format: format, register: false);

  Simulator.registerAction(10, () => a.put(0x2));
  Simulator.registerAction(20, () => a.put(0xf));
  await Simulator.run();
}

Map<String, Map<int, String>> _readVcdEvents(
    String path, Set<String> signalNames) {
  final lines = File(path).readAsLinesSync();
  final markerToSignal = <String, String>{};
  final markerToWidth = <String, int>{};
  final events = <String, Map<int, String>>{
    for (final name in signalNames) name: <int, String>{}
  };

  final sigNameRegexp = RegExp(
      r'\s*\$var\s(wire|reg)\s(\d+)\s(\S*)\s(\S*)\s+(\[\d+\:\d+\])?\s*\$end');
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
    String line, Map<String, int> markerToWidth) {
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

Map<String, Map<int, String>> _readFstEvents(String path,
    {required List<String> signalNames, required List<int> signalWidths}) {
  final data = File(path).readAsBytesSync();
  final events = <String, Map<int, String>>{
    for (final name in signalNames) name: <int, String>{}
  };

  var blockOffset = 0;
  while (blockOffset < data.length) {
    final blockType = data[blockOffset];
    final sectionLength = _readU64(data, blockOffset + 1);
    final blockEnd = blockOffset + 1 + sectionLength;

    if (blockType == 8) {
      _readFstVcDataBlock(data, blockOffset, blockEnd,
          signalNames: signalNames, signalWidths: signalWidths, events: events);
    }

    blockOffset = blockEnd;
  }

  return events;
}

void _readFstVcDataBlock(Uint8List data, int blockOffset, int blockEnd,
    {required List<String> signalNames,
    required List<int> signalWidths,
    required Map<String, Map<int, String>> events}) {
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
      frameUncompressed.value);
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
      timeUncompressedLength);
  final timeTable = _decodeTimeTable(timeBytes, timeCount);

  final chainLength = _readU64(data, timeDataStart - 8);
  final chainStart = timeDataStart - 8 - chainLength;
  final signalOffsets = _decodeFstOffsetChain(
      data.sublist(chainStart, timeDataStart - 8), valueMaxHandle.value);

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
    _decodeFstSignalData(data.sublist(signalDataStart, signalDataEnd),
        width: signalWidths[signalIndex],
        signalName: signalNames[signalIndex],
        timeTable: timeTable,
        events: events);
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

void _decodeFstSignalData(Uint8List bytes,
    {required int width,
    required String signalName,
    required List<int> timeTable,
    required Map<String, Map<int, String>> events}) {
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

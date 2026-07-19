// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flc_data_test.dart
// Unit tests for FlcData model: v5 trie-based FLC JSON parsing and
// signal lookup.

import 'package:rohd_source_navigator/flc_data.dart';
import 'package:test/test.dart';

void main() {
  group('FlcData.fromJson (v5 trie)', () {
    test('parses single-frame signal', () {
      final json = {
        'version': 5,
        'files': ['lib/src/foo.dart', 'lib/src/bar.dart'],
        'modules': {
          'TopModule': {
            'tree': [
              ['0:10:5', 'clk'],
              [
                '0:20:3',
                ['1:30:1', 'data']
              ],
              ['1:50:7', '*sub0'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      expect(flc.isEmpty, isFalse);
      expect(flc.files, ['lib/src/foo.dart', 'lib/src/bar.dart']);
      expect(flc.moduleNames, contains('TopModule'));

      // Single-frame signal.
      final clkFrames = flc.lookupSignal('TopModule', 'clk');
      expect(clkFrames, isNotNull);
      expect(clkFrames!.length, 1);
      expect(clkFrames[0].file, 'lib/src/foo.dart');
      expect(clkFrames[0].line, 10);
      expect(clkFrames[0].column, 5);

      // Multi-frame signal (outermost frame first in trie, reversed to
      // innermost-first in FlcEntry.frames).
      final dataFrames = flc.lookupSignal('TopModule', 'data');
      expect(dataFrames, isNotNull);
      expect(dataFrames!.length, 2);
      // Innermost first after reversal.
      expect(dataFrames[0].file, 'lib/src/bar.dart');
      expect(dataFrames[0].line, 30);
      expect(dataFrames[1].file, 'lib/src/foo.dart');
      expect(dataFrames[1].line, 20);

      // Instance lookup.
      final sub0Frames = flc.lookupInstance('TopModule', 'sub0');
      expect(sub0Frames, isNotNull);
      expect(sub0Frames!.length, 1);
      expect(sub0Frames[0].file, 'lib/src/bar.dart');
      expect(sub0Frames[0].line, 50);
    });

    test('parses signal with origName', () {
      final json = {
        'version': 5,
        'files': ['lib/src/adder.dart'],
        'modules': {
          'Adder': {
            'tree': [
              ['0:42:5', 'sum_0~sum'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);

      // Direct match by canonical name.
      final directFrames = flc.lookupSignal('Adder', 'sum_0');
      expect(directFrames, isNotNull);
      expect(directFrames![0].line, 42);

      // Fallback match by origName.
      final origFrames = flc.lookupSignal('Adder', 'sum');
      expect(origFrames, isNotNull);
      expect(origFrames![0].line, 42);
    });

    test('parses signal with SV position (legacy svFile)', () {
      final json = {
        'version': 5,
        'files': ['lib/src/foo.dart'],
        'modules': {
          'FilterBank': {
            'svFile': 'FilterBank.sv',
            'tree': [
              ['0:868:11', 'clk@2:13'],
              ['0:869:13', 'reset@3:13'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      expect(flc.isEmpty, isFalse);

      final clkEntry = flc.lookupSignalEntry('FilterBank', 'clk');
      expect(clkEntry, isNotNull);

      // SV frame via backward-compat getter.
      expect(clkEntry!.svFrame, isNotNull);
      expect(clkEntry.svFrame!.file, 'FilterBank.sv');
      expect(clkEntry.svFrame!.line, 2);
      expect(clkEntry.svFrame!.column, 13);
      expect(clkEntry.svFrame!.type, 'sv');

      // outputFrames list.
      expect(clkEntry.outputFrames.length, 1);
      expect(clkEntry.outputFrames[0].type, 'sv');

      // ROHD src frames.
      expect(clkEntry.frames.length, 1);
      expect(clkEntry.frames[0].file, 'lib/src/foo.dart');
      expect(clkEntry.frames[0].line, 868);
      expect(clkEntry.frames[0].column, 11);
      expect(clkEntry.frames[0].type, 'rohd');

      // allFrames returns output frames first, then ROHD.
      final allFrames = clkEntry.allFrames;
      expect(allFrames.length, 2);
      expect(allFrames[0].type, 'sv');
      expect(allFrames[1].type, 'rohd');
    });

    test('parses signal with outputFiles map', () {
      final json = {
        'version': 5,
        'files': ['lib/src/foo.dart'],
        'modules': {
          'FilterBank': {
            'outputFiles': {'sv': 'FilterBank.sv', 'sc': 'FilterBank.cpp'},
            'tree': [
              ['0:868:11', 'clk@sv:2:13;sc:10:5'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      final clkEntry = flc.lookupSignalEntry('FilterBank', 'clk');
      expect(clkEntry, isNotNull);

      // Two output frames.
      expect(clkEntry!.outputFrames.length, 2);
      expect(clkEntry.outputFrames[0].type, 'sv');
      expect(clkEntry.outputFrames[0].file, 'FilterBank.sv');
      expect(clkEntry.outputFrames[0].line, 2);
      expect(clkEntry.outputFrames[0].column, 13);
      expect(clkEntry.outputFrames[1].type, 'sc');
      expect(clkEntry.outputFrames[1].file, 'FilterBank.cpp');
      expect(clkEntry.outputFrames[1].line, 10);
      expect(clkEntry.outputFrames[1].column, 5);

      // Backward-compat svFrame returns the first SV frame.
      expect(clkEntry.svFrame, isNotNull);
      expect(clkEntry.svFrame!.type, 'sv');
      expect(clkEntry.svFrame!.line, 2);

      // allFrames: output frames first (2), then ROHD (1).
      expect(clkEntry.allFrames.length, 3);
    });

    test('parses multiple SV positions for same signal', () {
      final json = {
        'version': 5,
        'files': ['lib/src/foo.dart'],
        'modules': {
          'Top': {
            'outputFiles': {'sv': 'Top.sv'},
            'tree': [
              ['0:10:3', 'sig@sv:5:1;sv:20:3'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      final entry = flc.lookupSignalEntry('Top', 'sig');
      expect(entry, isNotNull);
      expect(entry!.outputFrames.length, 2);
      expect(entry.outputFrames[0].line, 5);
      expect(entry.outputFrames[1].line, 20);
      // svFrame returns the first one.
      expect(entry.svFrame!.line, 5);
    });

    test('sv frame is null when no svFile in module', () {
      final json = {
        'version': 5,
        'files': ['lib/src/foo.dart'],
        'modules': {
          'Combinational': {
            'tree': [
              ['0:10:3', 'out@5:1'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      final outEntry = flc.lookupSignalEntry('Combinational', 'out');
      expect(outEntry, isNotNull);
      // No svFile/outputFiles -> output frames should be empty.
      expect(outEntry!.svFrame, isNull);
      expect(outEntry.outputFrames, isEmpty);
      expect(outEntry.frames.length, 1);
      expect(outEntry.frames[0].type, 'rohd');
    });

    test('returns null for missing signals', () {
      final json = {
        'version': 5,
        'files': ['lib/src/top.dart'],
        'modules': {
          'Top': {
            'tree': [
              ['0:1:1', 'a'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      expect(flc.lookupSignal('Top', 'nonexistent'), isNull);
      expect(flc.lookupSignal('NonexistentModule', 'a'), isNull);
      expect(flc.lookupInstance('Top', 'a'), isNull);
    });

    test('returns empty FlcData when modules is null', () {
      final flc = FlcData.fromJson({'version': 5, 'files': []});
      expect(flc.isEmpty, isTrue);
      expect(flc.files, isEmpty);
    });

    test('returns empty FlcData when modules is empty', () {
      final flc = FlcData.fromJson({'version': 5, 'files': [], 'modules': {}});
      expect(flc.isEmpty, isTrue);
    });

    test('instance with SV position and origName', () {
      final json = {
        'version': 5,
        'files': ['lib/src/top.dart'],
        'modules': {
          'Top': {
            'svFile': 'Top.sv',
            'tree': [
              ['0:42:3', '*sub0@20:5~origSub'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      final entry = flc.lookupInstanceEntry('Top', 'sub0');
      expect(entry, isNotNull);
      expect(entry!.frames.length, 1);
      expect(entry.frames[0].line, 42);
      expect(entry.svFrame, isNotNull);
      expect(entry.svFrame!.line, 20);
      expect(entry.outputFrames.length, 1);
      expect(entry.outputFrames[0].type, 'sv');
      expect(entry.origName, 'origSub');

      // Fallback by origName.
      final byOrig = flc.lookupInstanceEntry('Top', 'origSub');
      expect(byOrig, isNotNull);
    });
  });

  group('FlcData.empty', () {
    test('creates empty instance', () {
      final flc = FlcData.empty();
      expect(flc.isEmpty, isTrue);
      expect(flc.files, isEmpty);
      expect(flc.moduleNames, isEmpty);
      expect(flc.lookupSignal('any', 'thing'), isNull);
    });
  });

  group('FlcData multi-module', () {
    test('handles multiple modules with shared files', () {
      final json = {
        'version': 5,
        'files': ['lib/src/shared.dart', 'lib/src/b_only.dart'],
        'modules': {
          'ModA': {
            'tree': [
              ['0:10:1', 'a'],
            ],
          },
          'ModB': {
            'tree': [
              ['1:20:1', 'b'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      expect(
        flc.files,
        containsAll(['lib/src/shared.dart', 'lib/src/b_only.dart']),
      );

      final aFrames = flc.lookupSignal('ModA', 'a');
      expect(aFrames, isNotNull);
      expect(aFrames![0].file, 'lib/src/shared.dart');

      final bFrames = flc.lookupSignal('ModB', 'b');
      expect(bFrames, isNotNull);
      expect(bFrames![0].file, 'lib/src/b_only.dart');
    });
  });

  group('FlcFrame edge cases', () {
    test('handles frame with only file:line (no column)', () {
      final json = {
        'version': 5,
        'files': ['lib/x.dart'],
        'modules': {
          'M': {
            'tree': [
              ['0:99', 's'],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      final frames = flc.lookupSignal('M', 's');
      expect(frames, isNotNull);
      expect(frames![0].line, 99);
      expect(frames[0].column, 1); // defaults to 1
    });

    test('skips malformed frame strings', () {
      final json = {
        'version': 5,
        'files': ['lib/x.dart'],
        'modules': {
          'M': {
            'tree': [
              [
                'bad',
                ['0:10:5', 's']
              ],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);
      final frames = flc.lookupSignal('M', 's');
      expect(frames, isNotNull);
      // 'bad' frame is skipped since file index parse fails.
      expect(frames!.length, 1);
      expect(frames[0].line, 10);
    });

    test('shared trie prefix produces correct frames', () {
      final json = {
        'version': 5,
        'files': ['lib/src/top.dart', 'lib/src/inner.dart'],
        'modules': {
          'Top': {
            'tree': [
              [
                '0:100:1', // shared outer frame
                ['1:10:5', 'sig1'],
                ['1:20:3', 'sig2'],
              ],
            ],
          },
        },
      };

      final flc = FlcData.fromJson(json);

      // Both signals share the outer frame 0:100:1.
      final sig1 = flc.lookupSignal('Top', 'sig1');
      expect(sig1, isNotNull);
      expect(sig1!.length, 2); // inner + outer
      // Innermost first after reversal.
      expect(sig1[0].line, 10);
      expect(sig1[1].line, 100);

      final sig2 = flc.lookupSignal('Top', 'sig2');
      expect(sig2, isNotNull);
      expect(sig2!.length, 2);
      expect(sig2[0].line, 20);
      expect(sig2[1].line, 100);
    });
  });
}

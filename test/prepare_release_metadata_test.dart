// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// prepare_release_metadata_test.dart
// Tests manifest-derived versions and metadata preparation in temporary files.
// No publication commands are invoked.
//
// Usage:
//   dart test test/prepare_release_metadata_test.dart
//
// 2026 September 18
// Author: Max Korbel <max.korbel@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageConfig = File('.dart_tool/package_config.json').absolute.path;
  late Directory fixture;

  File write(String path, String contents) {
    final file = File('${fixture.path}/$path');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  String read(String path) => File('${fixture.path}/$path').readAsStringSync();

  ProcessResult run(List<String> arguments) => Process.runSync(
        Platform.resolvedExecutable,
        [
          '--packages=$packageConfig',
          '${fixture.path}/tool/prepare_release_metadata.dart',
          ...arguments,
        ],
      );

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('release-metadata-');
    write('tool/prepare_release_metadata.dart',
        File('tool/prepare_release_metadata.dart').readAsStringSync());
    write('pubspec.yaml', 'name: rohd\nversion: "0.6.11" # release\n');
    write('CHANGELOG.md', '## Next Release\n\n- Update.\n');
    write('lib/src/utilities/config.dart',
        "static const String version = '0.6.10';\n");
    write('packages/rohd_hierarchy/pubspec.yaml', "version: '1.2.3'\n");
    write('packages/rohd_hierarchy/CHANGELOG.md', '## Next release\n');
    write('packages/rohd_waveform/pubspec.yaml', 'version: 2.3.4\n');
    write('packages/rohd_waveform/CHANGELOG.md', '## 2.3.4\n');
    write('packages/rohd_devtools_widgets/pubspec.yaml', 'version: 3.4.5\n');
    write('packages/rohd_devtools_widgets/CHANGELOG.md', '## Next Release\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  test('reads independent YAML versions without rewriting manifests', () {
    final manifest = read('pubspec.yaml');
    final result = run([
      'rohd',
      'rohd_hierarchy',
      'rohd_waveform',
      'rohd_devtools_widgets',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('rohd: 0.6.11 (prepared'));
    expect(result.stdout, contains('rohd_hierarchy: 1.2.3 (prepared'));
    expect(result.stdout, contains('rohd_waveform: 2.3.4 (prepared'));
    expect(result.stdout, contains('rohd_devtools_widgets: 3.4.5 (prepared'));
    expect(read('pubspec.yaml'), manifest);
    expect(read('CHANGELOG.md'), '## 0.6.11\n\n- Update.\n');
    expect(read('lib/src/utilities/config.dart'),
        "static const String version = '0.6.11';\n");
    expect(read('packages/rohd_hierarchy/CHANGELOG.md'), '## 1.2.3\n');
    expect(read('packages/rohd_waveform/CHANGELOG.md'), '## 2.3.4\n');
    expect(read('packages/rohd_devtools_widgets/CHANGELOG.md'), '## 3.4.5\n');
  });

  test('validation does not change metadata', () {
    final result = run(['--check', 'rohd', 'rohd_hierarchy']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('rohd: 0.6.11 (validated'));
    expect(read('CHANGELOG.md'), startsWith('## Next Release'));
    expect(read('lib/src/utilities/config.dart'), contains('0.6.10'));
    expect(read('packages/rohd_hierarchy/CHANGELOG.md'), '## Next release\n');
  });

  test('sub-package selection leaves ROHD unchanged', () {
    final result = run(['rohd_hierarchy']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(read('packages/rohd_hierarchy/CHANGELOG.md'), '## 1.2.3\n');
    expect(read('CHANGELOG.md'), startsWith('## Next Release'));
    expect(read('lib/src/utilities/config.dart'), contains('0.6.10'));
    expect(read('packages/rohd_devtools_widgets/CHANGELOG.md'),
        '## Next Release\n');
  });

  for (final manifest in [
    'name: rohd_hierarchy\n',
    'version: 12\n',
    'version: 1.2.3-rc.1\n',
    'version: [\n',
  ]) {
    test('rejects invalid manifest before any writes: ${manifest.trim()}', () {
      write('packages/rohd_hierarchy/pubspec.yaml', manifest);
      final result = run(['rohd', 'rohd_hierarchy']);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Release metadata:'));
      expect(read('CHANGELOG.md'), startsWith('## Next Release'));
      expect(read('lib/src/utilities/config.dart'), contains('0.6.10'));
    });
  }

  test('rejects missing changelog heading before any writes', () {
    write('packages/rohd_hierarchy/CHANGELOG.md', '## 0.1.0\n');
    final result = run(['rohd', 'rohd_hierarchy']);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('needs a'));
    expect(read('CHANGELOG.md'), startsWith('## Next Release'));
    expect(read('lib/src/utilities/config.dart'), contains('0.6.10'));
  });
}

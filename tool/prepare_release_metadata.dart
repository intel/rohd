// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// prepare_release_metadata.dart
// Prepare selected changelogs and ROHD's Config.version from package manifests.
// Validate all selected metadata before writing; never rewrite pubspec.yaml.
//
// Usage (normally invoked by tool/prepare_release.sh):
//   dart run tool/prepare_release_metadata.dart [--check] <package> [package ...]
//   dart run tool/prepare_release_metadata.dart --check rohd rohd_hierarchy
//
// --check validates and reports versions without writing files. This helper
// never invokes publication commands or performs Git operations.
//
// 2026 September 18
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:yaml/yaml.dart';

const _packagePaths = {
  'rohd': '.',
  'rohd_hierarchy': 'packages/rohd_hierarchy',
  'rohd_waveform': 'packages/rohd_waveform',
  'rohd_devtools_widgets': 'packages/rohd_devtools_widgets',
};

void main(List<String> arguments) {
  final checkOnly = arguments.isNotEmpty && arguments.first == '--check';
  final packages = checkOnly ? arguments.skip(1).toList() : arguments;
  final root = File.fromUri(Platform.script).parent.parent;

  try {
    if (packages.isEmpty) {
      throw const FormatException('Select at least one package.');
    }
    final updates = <File, String>{};
    final versions = <String, String>{};
    for (final package in packages.toSet()) {
      final relativePath = _packagePaths[package];
      if (relativePath == null) {
        throw FormatException('Unsupported package: $package');
      }
      final directory = '${root.path}/$relativePath';
      final manifestFile = File('$directory/pubspec.yaml');
      final Object? manifest = loadYaml(manifestFile.readAsStringSync());
      final Object? version = manifest is YamlMap ? manifest['version'] : null;
      if (version is! String || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
        throw FormatException(
            '${manifestFile.path} needs a stable major.minor.patch version.');
      }
      versions[package] = version;

      final changelog = File('$directory/CHANGELOG.md');
      final contents = changelog.readAsStringSync();
      final released =
          RegExp('^## ${RegExp.escape(version)}\r?\$', multiLine: true);
      final pending = RegExp(r'^## Next [Rr]elease\r?$', multiLine: true);
      if (!released.hasMatch(contents)) {
        if (!pending.hasMatch(contents)) {
          throw FormatException('${changelog.path} needs a '
              "'## Next Release' or '## $version' heading.");
        }
        updates[changelog] = contents.replaceFirst(pending, '## $version');
      }

      if (package == 'rohd') {
        final config = File('${root.path}/lib/src/utilities/config.dart');
        final contents = config.readAsStringSync();
        final declaration = RegExp("static const String version = '[^']*';");
        if (!declaration.hasMatch(contents)) {
          throw FormatException('${config.path} has no version declaration.');
        }
        updates[config] = contents.replaceFirst(
            declaration, "static const String version = '$version';");
      }
    }

    if (!checkOnly) {
      for (final update in updates.entries) {
        update.key.writeAsStringSync(update.value);
      }
    }
    for (final version in versions.entries) {
      stdout.writeln('${version.key}: ${version.value} '
          '(${checkOnly ? 'validated' : 'prepared'} from pubspec.yaml)');
    }
  } on Object catch (error) {
    stderr.writeln('Release metadata: $error');
    exitCode = 2;
  }
}

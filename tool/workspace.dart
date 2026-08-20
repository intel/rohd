// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// workspace.dart
// Pub workspace automation for ROHD packages.

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _usage = '''
Usage: dart run tool/workspace.dart <command>

Commands:
  analyze       Analyze every workspace package.
  clean         Delete build artifacts from every workspace package.
  test          Run native tests in every workspace package.
  test-node     Run Node.js tests in every non-Flutter workspace package.
  vscode        Generate rohd-multipackage.code-workspace.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      !{'analyze', 'clean', 'test', 'test-node', 'vscode'}
          .contains(arguments.single)) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }

  final root = Directory.current.absolute;
  final packages = _workspacePackages(root);
  final workspaceUsesFlutter = packages.any(_usesFlutter);

  if (arguments.single == 'vscode') {
    _generateVsCodeWorkspace(root, packages);
    return;
  }

  for (final package in packages) {
    final packageUsesFlutter = _usesFlutter(package);
    if (arguments.single == 'test-node' && packageUsesFlutter) {
      continue;
    }
    final command = packageUsesFlutter ||
            (arguments.single != 'test-node' &&
                package.path == root.path &&
                workspaceUsesFlutter)
        ? 'flutter'
        : 'dart';

    final commandArguments = switch (arguments.single) {
      'analyze' => const ['analyze', '--no-fatal-warnings'],
      'clean' => const ['clean'],
      'test' => const ['test'],
      'test-node' => const ['test', '--platform', 'node'],
      _ => throw StateError('Unexpected command.'),
    };
    await _run(command, commandArguments, package);
  }
}

List<Directory> _workspacePackages(Directory root) {
  final pubspec = _readPubspec(root);
  final workspace = pubspec['workspace'];
  if (workspace is! YamlList) {
    throw StateError('Root pubspec.yaml must declare a workspace list.');
  }

  return [
    root,
    for (final member in workspace)
      Directory('${root.path}${Platform.pathSeparator}$member').absolute,
  ];
}

bool _usesFlutter(Directory package) {
  final pubspec = _readPubspec(package);
  return _containsFlutterSdkDependency(pubspec['dependencies']) ||
      _containsFlutterSdkDependency(pubspec['dev_dependencies']);
}

bool _containsFlutterSdkDependency(Object? dependencies) {
  if (dependencies is! YamlMap) {
    return false;
  }
  final flutter = dependencies['flutter'];
  return flutter is YamlMap && flutter['sdk'] == 'flutter';
}

YamlMap _readPubspec(Directory package) {
  final pubspec = File('${package.path}${Platform.pathSeparator}pubspec.yaml');
  final parsed = loadYaml(pubspec.readAsStringSync());
  if (parsed is! YamlMap) {
    throw FormatException('Expected a YAML map in ${pubspec.path}.');
  }
  return parsed;
}

Future<void> _run(
  String command,
  List<String> arguments,
  Directory workingDirectory,
) async {
  stdout.writeln(
    'Running $command ${arguments.join(' ')} in ${workingDirectory.path}',
  );
  final process = await Process.start(
    command,
    arguments,
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(command, arguments, 'Command failed.', exitCode);
  }
}

void _generateVsCodeWorkspace(Directory root, List<Directory> packages) {
  final workspace = {
    'folders': [
      for (final package in packages)
        {
          'name': package.path == root.path ? 'rohd' : _baseName(package.path),
          'path': package.path == root.path
              ? '.'
              : package.path.substring(root.path.length + 1),
        },
    ],
    'settings': {'dart.projectSearchDepth': 8},
  };
  File('${root.path}${Platform.pathSeparator}rohd-multipackage.code-workspace')
      .writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(workspace)}\n',
  );
}

String _baseName(String path) {
  final separator = path.lastIndexOf(Platform.pathSeparator);
  return separator < 0 ? path : path.substring(separator + 1);
}

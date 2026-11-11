// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// test_devtools_install.dart
// Smoke-test that Flutter DevTools can discover the installed ROHD DevTools
// extension from a package root or extension/devtools install directory.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:devtools_shared/devtools_extensions_io.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--expect-absent') {
    final projectRoot = await _writeProjectRootPointingTo(
      Directory(p.normalize(p.absolute(args.last))),
      dependencyName: 'rohd',
    );
    try {
      final logs = <String>[];
      final manager = ExtensionsManager();
      await manager.serveAvailableExtensions(
        projectRoot.uri.toString(),
        logs,
        null,
      );
      if (manager.devtoolsExtensions.any((extension) =>
          extension.name == 'rohd_live_debugger' || extension.name == 'rohd')) {
        _fail('ROHD alone unexpectedly provides a DevTools extension.');
      }
      stdout.writeln('  ROHD alone does not provide a DevTools extension.');
    } finally {
      await projectRoot.delete(recursive: true);
    }
    return;
  }
  final targetPath =
      args.isEmpty ? '../packages/rohd_live_debugger' : args.single;
  final resolvedTarget = await _resolveTarget(targetPath);
  final targetDir = resolvedTarget.directory;

  if (!targetDir.existsSync()) {
    _fail('Expected target directory not found: ${targetDir.path}');
  }

  final install = await _resolveInstall(targetDir);
  final projectRoot = await _writeProjectRootPointingTo(install.root);

  try {
    final logs = <String>[];
    final manager = ExtensionsManager();
    await manager.serveAvailableExtensions(
      projectRoot.uri.toString(),
      logs,
      null,
    );

    final extensionAssetsPath = p.join(install.extensionDir.path, 'build');
    final rohdExtensions = manager.devtoolsExtensions
        .where(
          (extension) =>
              extension.name == 'rohd_live_debugger' &&
              p.equals(extension.extensionAssetsPath, extensionAssetsPath),
        )
        .toList();

    if (rohdExtensions.length != 1) {
      _fail(
        'Expected one available ROHD DevTools extension from '
        '${install.extensionDir.path}, found ${rohdExtensions.length}.\n'
        'Loader logs:\n${logs.join('\n')}',
      );
    }

    final extension = rohdExtensions.single;
    _requireValue(extension.displayName, 'displayName', 'rohd_live_debugger');
    _requireValue(
      extension.issueTrackerLink,
      'issueTracker',
      'https://github.com/intel/rohd/issues',
    );
    _requireNonEmpty(extension.version, 'version');
    _requireValue(
      extension.identifier,
      'identifier',
      'rohd_live_debugger_${extension.version}',
    );

    _requireFile(extensionAssetsPath, 'index.html');
    _requireFile(extensionAssetsPath, 'flutter_bootstrap.js');
    _requireFile(extensionAssetsPath, 'flutter.js');
    _requireFile(extensionAssetsPath, 'main.dart.js');
    _requireFile(extensionAssetsPath, 'version.json');
    final versionData = jsonDecode(
      File(p.join(extensionAssetsPath, 'version.json')).readAsStringSync(),
    );
    if (versionData is! Map<String, dynamic> ||
        versionData['version'] != extension.version) {
      _fail('Web build version does not match DevTools config '
          '"${extension.version}": $versionData');
    }
    _requireFile(extensionAssetsPath, p.join('assets', 'AssetManifest.bin'));
    _requireFile(extensionAssetsPath, p.join('assets', 'FontManifest.json'));
    _requireFile(extensionAssetsPath, p.join('canvaskit', 'canvaskit.js'));
    _requireFile(extensionAssetsPath, p.join('canvaskit', 'canvaskit.wasm'));
    _requireFile(
        extensionAssetsPath, p.join('dart_wellen', 'wellen_bridge.js'));
    _requireFile(
      extensionAssetsPath,
      p.join('dart_wellen', 'wellen_bridge_bg.wasm'),
    );

    stdout.writeln(
      '  DevTools loader found extension "${extension.name}" at '
      '${extension.extensionAssetsPath}',
    );
  } finally {
    await projectRoot.delete(recursive: true);
    await install.cleanupDir?.delete(recursive: true);
    await resolvedTarget.cleanupDir?.delete(recursive: true);
  }
}

Future<_ResolvedTarget> _resolveTarget(String target) async {
  final githubTree = _parseGithubTreeTarget(target);
  if (githubTree != null) {
    final resolved = await _downloadGithubTree(githubTree);
    return resolved;
  }

  if (target.startsWith('http://') || target.startsWith('https://')) {
    _fail(
      'Unsupported URL. Expected a GitHub tree URL like '
      'https://github.com/intel/rohd/tree/artifacts',
    );
  }

  return _ResolvedTarget(Directory(p.normalize(p.absolute(target))));
}

_GithubTreeTarget? _parseGithubTreeTarget(String target) {
  final uri = Uri.tryParse(target);
  if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.length >= 4 && segments[2] == 'tree') {
    return _GithubTreeTarget(
      owner: segments[0],
      repo: segments[1],
      branch: segments[3],
      treePath: segments.length > 4 ? p.joinAll(segments.skip(4)) : null,
    );
  }

  if (segments.length >= 3 && segments[0] == 'rohd' && segments[1] == 'tree') {
    return _GithubTreeTarget(
      owner: 'intel',
      repo: 'rohd',
      branch: segments[2],
      treePath: segments.length > 3 ? p.joinAll(segments.skip(3)) : null,
    );
  }

  return null;
}

Future<_ResolvedTarget> _downloadGithubTree(_GithubTreeTarget target) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'rohd_devtools_install_tree_',
  );
  final archivePath = p.join(
    tempDir.path,
    '${target.repo}-${target.branch}.zip',
  );
  final archiveUrl = 'https://github.com/${target.owner}/${target.repo}/'
      'archive/refs/heads/${target.branch}.zip';

  await _runChecked('curl', ['-fsSL', archiveUrl, '-o', archivePath]);
  await _runChecked('unzip', ['-q', archivePath, '-d', tempDir.path]);

  final extractedRoot = Directory(
    p.join(tempDir.path, '${target.repo}-${target.branch}'),
  );
  final resolvedPath = target.treePath == null || target.treePath!.isEmpty
      ? extractedRoot.path
      : p.join(extractedRoot.path, target.treePath);

  return _ResolvedTarget(Directory(resolvedPath), cleanupDir: tempDir);
}

Future<void> _runChecked(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    _fail(
      'Failed to run `$executable ${arguments.join(' ')}`\n'
      '${result.stderr}',
    );
  }
}

final class _GithubTreeTarget {
  final String owner;
  final String repo;
  final String branch;
  final String? treePath;

  const _GithubTreeTarget({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.treePath,
  });
}

final class _ResolvedTarget {
  final Directory directory;
  final Directory? cleanupDir;

  const _ResolvedTarget(this.directory, {this.cleanupDir});
}

final class _ResolvedInstall {
  final Directory root;
  final Directory extensionDir;
  final Directory? cleanupDir;

  const _ResolvedInstall({
    required this.root,
    required this.extensionDir,
    this.cleanupDir,
  });
}

Future<_ResolvedInstall> _resolveInstall(Directory extensionDir) async {
  final extensionParent = extensionDir.parent;
  if (p.basename(extensionDir.path) == 'devtools' &&
      p.basename(extensionParent.path) == 'extension') {
    final installRoot = extensionParent.parent;
    if (File(p.join(installRoot.path, 'pubspec.yaml')).existsSync()) {
      return _ResolvedInstall(
        root: installRoot,
        extensionDir: extensionDir,
      );
    }

    return _createStandaloneInstall(extensionDir);
  }

  final nestedExtensionDir = Directory(
    p.join(extensionDir.path, 'extension', 'devtools'),
  );
  if (nestedExtensionDir.existsSync() &&
      File(p.join(extensionDir.path, 'pubspec.yaml')).existsSync()) {
    return _ResolvedInstall(
      root: extensionDir,
      extensionDir: nestedExtensionDir,
    );
  }

  _fail(
    'Expected target to be a package root containing extension/devtools or the '
    'extension/devtools directory itself, got ${extensionDir.path}',
  );
}

Future<_ResolvedInstall> _createStandaloneInstall(
  Directory extensionDir,
) async {
  final root = await Directory.systemTemp.createTemp(
    'rohd_devtools_extension_package_',
  );
  final stagedExtensionDir = Directory(
    p.join(root.path, 'extension', 'devtools'),
  );
  await _copyDirectory(extensionDir, stagedExtensionDir);
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: rohd_live_debugger
environment:
  sdk: ^3.6.0
''');

  return _ResolvedInstall(
    root: root,
    extensionDir: stagedExtensionDir,
    cleanupDir: root,
  );
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relativePath = p.relative(entity.path, from: source.path);
    final destinationPath = p.join(destination.path, relativePath);
    if (entity is Directory) {
      await Directory(destinationPath).create(recursive: true);
    } else if (entity is File) {
      await entity.copy(destinationPath);
    } else {
      _fail(
        'Unsupported file-system entry in extension artifact: ${entity.path}',
      );
    }
  }
}

Future<Directory> _writeProjectRootPointingTo(
  Directory packageRoot, {
  String dependencyName = 'rohd_live_debugger',
}) async {
  final projectRoot = await Directory.systemTemp.createTemp(
    'rohd_devtools_extension_discovery_',
  );
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  await pubspec.writeAsString('''
name: rohd_devtools_extension_discovery
environment:
  sdk: ^3.6.0
dependencies:
  $dependencyName:
    path: ${jsonEncode(packageRoot.path)}
''');
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['pub', 'get'],
    workingDirectory: projectRoot.path,
  );
  if (result.exitCode != 0) {
    _fail(
      'Failed to resolve the temporary DevTools discovery project.\n'
      '${result.stderr}',
    );
  }

  return projectRoot;
}

void _requireValue(String value, String key, String expectedValue) {
  if (value != expectedValue) {
    _fail('Expected config "$key" to be "$expectedValue", got "$value".');
  }
}

void _requireNonEmpty(String value, String key) {
  if (value.isEmpty) {
    _fail('Expected config "$key" to be a non-empty string, got "$value".');
  }
}

void _requireFile(String root, String relativePath) {
  final file = File(p.join(root, relativePath));
  if (!file.existsSync()) {
    _fail('Expected file not found: ${file.path}');
  }
}

Never _fail(String message) {
  stderr.writeln('  $message');
  exit(1);
}

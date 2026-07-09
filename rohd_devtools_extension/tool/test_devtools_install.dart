// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// test_devtools_install.dart
// Smoke-test that Flutter DevTools can discover the installed ROHD DevTools
// extension from a package root or extension/devtools install directory.

import 'dart:convert';
import 'dart:io';

import 'package:devtools_shared/devtools_extensions_io.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final targetPath = args.isEmpty ? '../extension/devtools' : args.single;
  final targetDir = Directory(p.normalize(p.absolute(targetPath)));

  if (!targetDir.existsSync()) {
    _fail('Expected target directory not found: ${targetDir.path}');
  }

  final installRoot = _installRootFor(targetDir);
  final extensionDir =
      Directory(p.join(installRoot.path, 'extension', 'devtools'));
  final projectRoot = await _writeProjectRootPointingTo(installRoot);

  try {
    final logs = <String>[];
    final manager = ExtensionsManager();
    await manager.serveAvailableExtensions(
      projectRoot.uri.toString(),
      logs,
      null,
    );

    final extensionAssetsPath = p.join(extensionDir.path, 'build');
    final rohdExtensions = manager.devtoolsExtensions.where((extension) {
      return extension.name == 'rohd' &&
          p.equals(
            extension.extensionAssetsPath,
            extensionAssetsPath,
          );
    }).toList();

    if (rohdExtensions.length != 1) {
      _fail(
        'Expected one available ROHD DevTools extension from '
        '${extensionDir.path}, found ${rohdExtensions.length}.\n'
        'Loader logs:\n${logs.join('\n')}',
      );
    }

    final extension = rohdExtensions.single;
    _requireValue(extension.issueTrackerLink, 'issueTracker',
        'https://github.com/intel/rohd/issues');
    _requireNonEmpty(extension.version, 'version');

    _requireFile(extensionAssetsPath, 'index.html');
    _requireFile(extensionAssetsPath, 'flutter_bootstrap.js');
    _requireFile(extensionAssetsPath, 'flutter.js');
    _requireFile(extensionAssetsPath, 'main.dart.js');
    _requireFile(extensionAssetsPath, 'version.json');
    _requireFile(extensionAssetsPath, p.join('assets', 'AssetManifest.json'));
    _requireFile(extensionAssetsPath, p.join('assets', 'FontManifest.json'));
    _requireFile(extensionAssetsPath, p.join('canvaskit', 'canvaskit.js'));
    _requireFile(extensionAssetsPath, p.join('canvaskit', 'canvaskit.wasm'));

    stdout.writeln(
      '  DevTools loader found extension "${extension.name}" at '
      '${extension.extensionAssetsPath}',
    );
  } finally {
    await projectRoot.delete(recursive: true);
  }
}

Directory _installRootFor(Directory extensionDir) {
  final extensionParent = extensionDir.parent;
  if (p.basename(extensionDir.path) == 'devtools' &&
      p.basename(extensionParent.path) == 'extension') {
    return extensionParent.parent;
  }

  final nestedExtensionDir =
      Directory(p.join(extensionDir.path, 'extension', 'devtools'));
  if (nestedExtensionDir.existsSync()) {
    return extensionDir;
  }

  _fail(
    'Expected target to be a package root containing extension/devtools or the '
    'extension/devtools directory itself, got ${extensionDir.path}',
  );
}

Future<Directory> _writeProjectRootPointingTo(Directory packageRoot) async {
  final projectRoot = await Directory.systemTemp.createTemp(
    'rohd_devtools_extension_discovery_',
  );
  final dartToolDir = Directory(p.join(projectRoot.path, '.dart_tool'));
  dartToolDir.createSync(recursive: true);
  final packageConfigFile =
      File(p.join(dartToolDir.path, 'package_config.json'));
  packageConfigFile.writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'rohd',
          'rootUri': packageRoot.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.6',
        }
      ],
    }),
  );
  return projectRoot;
}

void _requireValue(
  String value,
  String key,
  String expectedValue,
) {
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

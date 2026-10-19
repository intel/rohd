// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Verifies that the DevTools application resolves ROHD packages from this
// monorepo checkout rather than from hosted pub.dev packages.

import 'dart:convert';
import 'dart:io';

void main() {
  final extensionRoot = Directory.current.absolute;
  final repositoryRoot = Directory(extensionRoot.parent.path);
  final packageConfig = File(
    '${repositoryRoot.path}/.dart_tool/package_config.json',
  );

  if (!packageConfig.existsSync()) {
    _fail(
      'Missing ${packageConfig.path}. Run `flutter pub get` from the '
      'workspace root before verifying local package resolution.',
    );
  }

  final decoded = jsonDecode(packageConfig.readAsStringSync());
  if (decoded is! Map<String, dynamic> || decoded['packages'] is! List) {
    _fail('Invalid package config: ${packageConfig.path}');
  }

  final expectedRoots = <String, Directory>{
    'rohd': repositoryRoot,
    'rohd_hierarchy':
        Directory('${repositoryRoot.path}/packages/rohd_hierarchy'),
    'rohd_waveform': Directory('${repositoryRoot.path}/packages/rohd_waveform'),
    'rohd_devtools_widgets':
        Directory('${repositoryRoot.path}/packages/rohd_devtools_widgets'),
    'rohd_source_navigator':
        Directory('${repositoryRoot.path}/packages/rohd_source_navigator'),
  };
  final packageRoots = <String, String>{};

  for (final entry in decoded['packages'] as List<dynamic>) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final name = entry['name'];
    final rootUri = entry['rootUri'];
    if (name is String && rootUri is String) {
      packageRoots[name] = _rootPath(rootUri, packageConfig.parent);
    }
  }

  for (final entry in expectedRoots.entries) {
    final resolvedRoot = packageRoots[entry.key];
    if (resolvedRoot == null) {
      _fail('Package config does not resolve required package ${entry.key}.');
    }

    final expectedRoot = _canonicalPath(entry.value);
    if (_canonicalPath(Directory(resolvedRoot)) != expectedRoot) {
      _fail(
        'Package ${entry.key} resolved to $resolvedRoot; expected '
        '${entry.value.path}. Ensure the package is a workspace member and '
        'run `flutter pub get` from the workspace root.',
      );
    }
    stdout.writeln('  ${entry.key}: $resolvedRoot');
  }
}

String _rootPath(String rootUri, Directory packageConfigDirectory) {
  final uri = Uri.tryParse(rootUri);
  if (uri == null) {
    _fail('Package config contains an invalid root URI: $rootUri');
  }
  final resolvedUri =
      uri.scheme.isEmpty ? packageConfigDirectory.uri.resolveUri(uri) : uri;
  if (resolvedUri.scheme != 'file') {
    _fail('Package config contains a non-file root URI: $rootUri');
  }
  return resolvedUri.toFilePath();
}

String _canonicalPath(Directory directory) {
  if (!directory.existsSync()) {
    _fail('Expected local package directory does not exist: ${directory.path}');
  }
  return directory.resolveSymbolicLinksSync();
}

Never _fail(String message) {
  stderr.writeln('  $message');
  exit(1);
}

import 'dart:convert';
import 'dart:io';

Never fail(String message) {
  stderr.writeln('error: $message');
  exit(2);
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    fail(
      'Usage: dart scripts/resolve_package_root.dart '
      '<package-config> <package-name>',
    );
  }

  final packageConfig = File(arguments[0]);
  if (!packageConfig.existsSync()) {
    fail(
      'Package configuration does not exist: ${packageConfig.path}. '
      'Run flutter pub get first.',
    );
  }

  final dynamic decodedConfig;
  try {
    decodedConfig = jsonDecode(packageConfig.readAsStringSync());
  } on FormatException catch (error) {
    fail('Invalid package configuration ${packageConfig.path}: $error');
  }

  if (decodedConfig is! Map) {
    fail('Invalid package configuration ${packageConfig.path}.');
  }

  final packages = decodedConfig['packages'];
  if (packages is! List) {
    fail('Package configuration ${packageConfig.path} has no package list.');
  }

  final packageName = arguments[1];
  for (final package in packages) {
    if (package is! Map || package['name'] != packageName) {
      continue;
    }

    final rootUriText = package['rootUri'];
    if (rootUriText is! String) {
      fail('Package $packageName has no root URI.');
    }

    final rootUri = packageConfig.parent.uri.resolve(rootUriText);
    if (rootUri.scheme != 'file') {
      fail('Package $packageName has a non-file root URI: $rootUri.');
    }

    final packageRoot = Directory.fromUri(rootUri);
    if (!packageRoot.existsSync()) {
      fail('Package $packageName does not exist at ${packageRoot.path}.');
    }

    stdout.writeln(packageRoot.path);
    return;
  }

  fail('Package $packageName is not in ${packageConfig.path}.');
}

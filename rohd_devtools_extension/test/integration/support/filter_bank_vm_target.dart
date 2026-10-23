// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_vm_target.dart
// Launches and manages the FilterBank VM integration-test target.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FilterBankVmTarget {
  final Process _process;
  final String serviceUri;
  final List<StreamSubscription<String>> _subscriptions;

  FilterBankVmTarget._({
    required Process process,
    required this.serviceUri,
    required List<StreamSubscription<String>> subscriptions,
  })  : _process = process,
        _subscriptions = subscriptions;

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    if (_process.kill()) {
      try {
        await _process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _process.kill(ProcessSignal.sigkill);
        await _process.exitCode;
      }
    }
  }
}

Future<FilterBankVmTarget> startFilterBankVmTarget() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final bundledDart = flutterRoot == null
      ? null
      : File('$flutterRoot/bin/cache/dart-sdk/bin/dart');
  final dartExecutable = bundledDart != null && bundledDart.existsSync()
      ? bundledDart.path
      : 'dart';
  final process = await Process.start(
    dartExecutable,
    [
      '--enable-vm-service=0',
      'test/integration/fixtures/filter_bank_vm_target.dart',
    ],
    workingDirectory: Directory.current.path,
  );
  final serviceUri = Completer<String>();
  final ready = Completer<void>();
  final logs = StringBuffer();
  final subscriptions = <StreamSubscription<String>>[];

  void handleLine(String line) {
    logs.writeln(line);
    if (line.contains('VM service is listening')) {
      final uri = RegExp(r'https?://[^\s]+').firstMatch(line)?.group(0);
      if (uri != null && !serviceUri.isCompleted) {
        serviceUri.complete(uri);
      }
    }
    if (line == 'ROHD_VM_TARGET_READY' && !ready.isCompleted) {
      ready.complete();
    }
  }

  for (final stream in [process.stdout, process.stderr]) {
    subscriptions.add(
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine),
    );
  }
  unawaited(
    process.exitCode.then((exitCode) {
      final error = StateError(
        'FilterBank VM target exited before becoming ready ($exitCode):\n$logs',
      );
      if (!serviceUri.isCompleted) {
        serviceUri.completeError(error);
      }
      if (!ready.isCompleted) {
        ready.completeError(error);
      }
    }),
  );

  try {
    await Future.wait([serviceUri.future, ready.future]).timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw StateError(
        'FilterBank VM target did not become ready:\n$logs',
      ),
    );
  } on Object {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    process.kill();
    rethrow;
  }

  return FilterBankVmTarget._(
    process: process,
    serviceUri: await serviceUri.future,
    subscriptions: subscriptions,
  );
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Runnable cross-probe button Flutter example.
//
// 2026 September 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() => runApp(const CrossProbeExample());

class CrossProbeExample extends StatefulWidget {
  const CrossProbeExample({super.key});

  @override
  State<CrossProbeExample> createState() => _CrossProbeExampleState();
}

class _CrossProbeExampleState extends State<CrossProbeExample> {
  final _channel = LocalCrossProbeChannel();
  late final LocalCrossProbeService _service = LocalCrossProbeService(
    _channel,
    source: 'example',
  );

  @override
  void dispose() {
    _service.dispose();
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Cross-probe example')),
          body: Center(child: CrossProbeButton(service: _service)),
        ),
      );
}

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Runnable FLC source-location lookup example.
//
// 2026 September 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_source_navigator/flc_data.dart';

void main() {
  final data = FlcData.fromJson({
    'version': 5,
    'files': ['lib/top.dart'],
    'modules': {
      'Top': {
        'tree': [
          ['0:42:5', 'result'],
        ],
      },
    },
  });

  final frames = data.lookupSignal('Top', 'result');
  if (frames?.single.line != 42) {
    throw StateError('Expected the result signal at lib/top.dart:42.');
  }
}

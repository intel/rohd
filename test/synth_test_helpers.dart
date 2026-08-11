// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_test_helpers.dart
// Shared helpers for stable synthesized-output test comparisons.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Normalizes timestamped synth headers so full-output comparisons are stable.
String normalizeSynthHeader(String synth) => synth.replaceAll(
    RegExp(r'Generation time:.*\n'), 'Generation time: <normalized>\n');

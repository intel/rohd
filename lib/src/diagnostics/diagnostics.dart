// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// diagnostics.dart
// Barrel export for the diagnostics library.
//
// 2026 July 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Retained so existing users can migrate from FlcService to TraceService.
// ignore: deprecated_member_use_from_same_package
export 'flc_service.dart' show FlcService;
export 'module_service.dart';
export 'module_services.dart';
export 'trace_service.dart';
export 'waveform_data_service.dart';
export 'waveform_service.dart';
export 'waveform_writer.dart';

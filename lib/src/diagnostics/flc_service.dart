// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flc_service.dart
// Backwards-compatible alias for TraceService.
//
// 2026 June 23
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/diagnostics/trace_service.dart';

export 'package:rohd/src/diagnostics/trace_service.dart';

/// Deprecated alias for the trace lookup service.
@Deprecated('Use TraceService instead.')
typedef FlcService = TraceService;

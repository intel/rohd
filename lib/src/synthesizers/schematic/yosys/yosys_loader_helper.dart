// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// yosys_loader_helper.dart
// A helper routine to load a Yosys JSON file using the D3 ELK loader.
//
// 2025 December 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Conditional export: use IO implementation on VM, JS implementation on web
export 'yosys_loader_io.dart'
    if (dart.library.js_interop) 'yosys_loader_web.dart';

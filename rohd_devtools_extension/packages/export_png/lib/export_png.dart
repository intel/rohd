// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// export_png.dart
// Platform-conditional PNG export utilities shared across ROHD DevTools
// sub-packages (schematic viewer, waveform viewer, etc.).
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'src/save_png_stub.dart'
    if (dart.library.io) 'src/save_png_native.dart'
    if (dart.library.js_interop) 'src/save_png_web.dart';
export 'src/capture_boundary.dart';
export 'src/export_button.dart';
export 'src/export_toast.dart';

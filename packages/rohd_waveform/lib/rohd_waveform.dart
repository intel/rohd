// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_waveform.dart
// Waveform data models and APIs for wave viewers.
//
// 2026 July 15
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Waveform data models and APIs for wave viewers.
///
/// This library provides waveform-specific data models:
/// - `ModuleStructure` - top-level waveform structure
/// - `SignalWaveform` - waveform data with backpointer to signal metadata
/// - `Data`, `WaveFormat`, and `MetaData` - waveform data primitives
///
/// For hierarchy types such as `HierarchyOccurrence` and `SignalOccurrence`,
/// import 'package:rohd_hierarchy/rohd_hierarchy.dart' directly.
library;

export 'src/models/models.dart';
export 'src/waveform_api.dart';
export 'src/waveform_repository.dart';

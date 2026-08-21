// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_sample.dart
// LogicStructure sample word for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// A structured signal bundling a data sample with metadata.
///
/// Packs three fields — [data], and [valid] — into a single
/// bus that can be driven and sampled as a unit.  Used throughout the
/// filter bank to carry tagged samples between modules.
class FilterSample extends LogicStructure {
  /// The sample data word.
  late final Logic data;

  /// Whether this sample is valid.
  late final Logic valid;

  /// Creates a [FilterSample] with the given [dataWidth] (default 16)
  /// and optional [name].
  FilterSample({int dataWidth = 16, String? name})
      : super(
          [
            Logic(name: 'data', width: dataWidth),
            Logic(name: 'valid'),
          ],
          name: name ?? 'filter_sample',
        ) {
    data = elements[0];
    valid = elements[1];
  }

  // Private constructor for clone to share element structure.
  FilterSample._clone(super.elements, {required super.name}) {
    data = elements[0];
    valid = elements[1];
  }

  @override

  /// Returns a structural clone of this sample, preserving element names.
  FilterSample clone({String? name}) => FilterSample._clone(
        elements.map((e) => e.clone(name: e.name)),
        name: name ?? this.name,
      );
}

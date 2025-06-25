// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_file_contents.dart
// Definition for `SynthFileContents`
//
// 2025 June 24
// Author: Max Korbel <max.korbel@intel.com>

/// Represents contents of a file.
class SynthFileContents {
  /// The name of the content or file.
  final String name;

  /// An (optional) description of what this represents.
  final String? description;

  /// The actual contents of the file.
  final String contents;

  /// Creates a new [SynthFileContents].
  const SynthFileContents(
      {required this.name, required this.contents, this.description});

  @override
  String toString() => contents;
}

// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// write_after_read_exception.dart
// An exception thrown when a "write after read" violation occurs.
//
// 2023 April 13
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when a "write after read" violation occurs.
///
/// This is also sometimes called a "read before write" violation.
class WriteAfterReadException extends RohdException {
  final List<String>? _path;

  /// Creates a [WriteAfterReadException].
  WriteAfterReadException() : this._();

  /// Creates a [WriteAfterReadException].
  WriteAfterReadException._([this._path])
      : super(_appendPath(
            'Signal changed its value after being used'
            ' within one `Combinational` execution.'
            ' This can lead to a mismatch between simulation and synthesis.'
            ' You may be able to use `Combinational.ssa` to correct your'
            ' design with minimal refactoring.',
            _path));

  /// Appends a [path] to the [message], if it exists.
  static String _appendPath(String message, List<String>? path) {
    if (path == null || path.isEmpty) {
      return message;
    }
    return '$message\n${path.join('\n')}';
  }

  /// Clones this [WriteAfterReadException] with an added [pathItem] item to the
  /// top of the path.
  @internal
  WriteAfterReadException cloneWithAddedPath(String pathItem) =>
      WriteAfterReadException._([
        pathItem,
        if (_path != null) ...?_path,
      ]);
}

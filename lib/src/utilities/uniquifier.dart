// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// uniquifier.dart
// Efficient implementation to provide unique names
//
// 2021 July 13
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';

/// An object that can provide uniquified names in an efficient way.
///
/// The object keeps state about past names that have been provided, so should
/// be maintained for as long as new names in some scope will need to be
/// generated.
class Uniquifier {
  /// A collection of counters for names to keep track where it left off last
  /// time.
  final Map<String, int> _nameCounters = <String, int>{};

  /// A [Set] of names already accessed via [getUniqueName()].
  late final Set<String> takenNames = UnmodifiableSetView(_takenNames);
  final Set<String> _takenNames = HashSet<String>();

  /// A [Set] of names that are reserved, including originally pre-reserved ones
  /// and ones already taken.
  late final Set<String> reservedNames = UnmodifiableSetView(_reservedNames);
  final Set<String> _reservedNames;

  /// Constructs a new [Uniquifier], optionally with a set of
  /// pre-[reservedNames].
  Uniquifier({Set<String>? reservedNames})
      : _reservedNames = reservedNames ?? {};

  /// Returns `true` iff [name] is exactly available without uniquification.
  ///
  /// If [reserved] is set to `true`, then it will return that the [name] is
  /// available if it is reserved but not yet taken.
  bool isAvailable(String name, {bool reserved = false}) =>
      !_takenNames.contains(name) &&
      (reserved || !_reservedNames.contains(name));

  /// Provides a uniquified name that has never been returned by this
  /// [Uniquifier].
  ///
  /// If it is specified and there is no conflict, it will always choose
  /// [initialName]. If no [initialName] is specified, it will name it using
  /// [nullStarter]. From the starting point, it will increment an integer
  /// appended to the end until no more conflict exists.
  ///
  /// Setting [reserved] will ensure the name does not get modified from its
  /// original name. If a reserved name is already taken, an exception will be
  /// thrown.
  String getUniqueName(
      {String? initialName, bool reserved = false, String nullStarter = 'i'}) {
    String actualName;

    if (reserved) {
      if (initialName == null) {
        throw NullReservedNameException();
      } else if (initialName.isEmpty) {
        throw EmptyReservedNameException();
      } else if (!isAvailable(initialName, reserved: reserved)) {
        throw UnavailableReservedNameException(initialName);
      }

      actualName = initialName;
    } else {
      final requestedName = initialName ?? nullStarter;

      actualName = requestedName;

      while (!isAvailable(actualName, reserved: reserved)) {
        // initialize counter if necessary
        _nameCounters[requestedName] ??= -1; // first one should be 0

        _nameCounters[requestedName] = _nameCounters[requestedName]! + 1;
        actualName = '${requestedName}_${_nameCounters[requestedName]!}';
      }
    }

    _takenNames.add(actualName);
    return actualName;
  }
}

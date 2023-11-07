// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// name_validator.dart
// Performs validation on naming.
//
// 2023 October 24

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

//// Configuration options and utilities for naming and renaming signals.
enum Naming {
  /// The signal will be present in generated output and the name will not be
  /// changed.
  ///
  /// If this is not achievable, an [Exception] will be thrown.
  reserved,

  /// The signal will be present in generated output, but the signal may be
  /// renamed for uniqueness. It will not be merged into any other signals.
  renameable,

  /// The signal may be merged with other equivalent signals in generated
  /// outputs, and any of the names from the merged signals may be selected.
  mergeable,

  /// This signal has no given name and generated output will attempt to name
  /// it as best as it can.
  unnamed;

  /// Returns [name] if it meets requirements for the specified [reserveName],
  /// otherwise throws an [Exception].
  ///
  /// This same function is reusable for other reference names like [Module]s,
  /// not only [Logic]s.
  static String? validatedName(String? name, {required bool reserveName}) {
    if (reserveName) {
      if (name == null) {
        throw NullReservedNameException();
      } else if (name.isEmpty) {
        throw EmptyReservedNameException();
      } else if (!Sanitizer.isSanitary(name)) {
        throw InvalidReservedNameException();
      }
    }

    return name;
  }

  /// A prefix to add to the beginning of any port name that is "unpreferred".
  static String get _unpreferredPrefix => '_';

  /// Makes a signal name "unpreferred" when considering between multiple
  /// possible signal names.
  ///
  /// When logic is synthesized out (e.g. to SystemVerilog), there are cases
  /// where two signals might be logically equivalent (e.g. directly connected
  /// to each other). In those scenarios, one of the two signals is collapsed
  /// into the other. If one of the two signals is "unpreferred", it will
  /// choose the other one for the final signal name.  Marking signals as
  /// "unpreferred" can have the effect of making generated output easier to
  /// read.
  static String unpreferredName(String name) => _unpreferredPrefix + name;

  /// Returns true iff the signal name is "unpreferred".
  ///
  /// See documentation for [unpreferredName] for more details.
  static bool isUnpreferred(String name) => name.startsWith(_unpreferredPrefix);

  /// Picks a [Naming] based on an initial [name] and [naming].
  static Naming chooseNaming(String? name, Naming? naming) =>
      naming ??
      ((name != null && name.isNotEmpty)
          ? Naming.isUnpreferred(name)
              ? Naming.mergeable
              : Naming.renameable
          : Naming.unnamed);

  /// Picks a [String] name based on an initial [name] and [naming].
  ///
  /// If [name] is null, the name will be based on [nullStarter].
  static String chooseName(String? name, Naming? naming,
          {String nullStarter = 's'}) =>
      naming == Naming.reserved
          ? Naming.validatedName(name, reserveName: true)!
          : (name == null || name.isEmpty)
              ? Naming.unpreferredName(nullStarter)
              : Sanitizer.sanitizeSV(name);
}

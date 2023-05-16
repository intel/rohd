/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause

library values;

import 'dart:math';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/exceptions.dart';

part 'logic_value.dart';
part 'small_logic_value.dart';
part 'big_logic_value.dart';
part 'filled_logic_value.dart';

/// Allows random generation of [LogicValue] for [BigInt] and [int].
extension RandLogicValue on Random {
  /// Generate non-negative random [LogicValue] of [int] that uniformly
  /// distributed in the range from [min], inclusive, to [max], exclusive.
  ///
  /// Example:
  ///
  /// ```dart
  /// final lvInt = Random(10).nextLogicValueInt(min: 20, max: 100);
  /// ```
  LogicValue nextLogicValueInt({required int max, int min = 0}) {
    final randInt = nextInt(max) + min;
    final width = randInt.bitLength;

    return LogicValue.ofInt(randInt, width);
  }

  /// Generate non-negative random [BigInt] value that consists of
  /// [numBits] bits.
  ///
  /// Example:
  ///
  /// ```dart
  /// // generate 100 bits of random BigInt
  /// final bigInt = Random(10).nextBigInt(numBits: 100);
  /// ```
  BigInt nextBigInt({required int numBits}) {
    final bitString = StringBuffer('1');
    for (var i = 1; i < numBits; i++) {
      bitString.write(nextInt(2).toString());
    }

    return BigInt.parse(bitString.toString(), radix: 2);
  }

  /// Generate non-negative random [BigInt]'s [LogicValue] that consists of
  /// [numBits] bits.
  ///
  /// Example:
  ///
  /// ```dart
  /// // generate 100 bits of random BigInt LogicValue
  /// final lvBigInt = Random(10).nextLogicValueBigInt(numBits: 100);
  /// ```
  LogicValue nextLogicValueBigInt(
      {required int numBits, bool hasInvalidBits = false}) {
    final randBigInt = nextBigInt(numBits: numBits);
    final width = randBigInt.bitLength;

    return LogicValue.ofBigInt(randBigInt, width);
  }

  LogicValue nextLogicValue({
    required int width,
    int? max,
    bool hasInvalidBits = false,
    int min = 0,
  }) {
    final candidatePool =
        hasInvalidBits == false ? ['1', '0'] : ['1', '0', 'x', 'z'];
    final bitString = StringBuffer();

    if (hasInvalidBits) {
      // Generate based on width given
      for (var i = 0; i < width; i++) {
        bitString.write(candidatePool[nextInt(4)]);
      }

      return LogicValue.of([LogicValue.ofString(bitString.toString())]);
    } else {
      // Generate the random value of range between min and max
      // that are still within width
    }

    return LogicValue.one;
  }
}

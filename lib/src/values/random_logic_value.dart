// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// random_logic_value.dart
// Random Logic Value generation extension.
//
// 2023 May 18
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

part of 'values.dart';

/// Allows random generation of [LogicValue] for [BigInt] and [int].
extension RandLogicValue on math.Random {
  /// Generate unsigned random [BigInt] value that consists of
  /// [numBits] bits.
  BigInt _nextBigInt({required int numBits}) {
    var result = BigInt.zero;
    for (var i = 0; i < numBits; i += 32) {
      // BigInt is safe with it, though
      result = (result << 32) | BigInt.from(nextInt(oneSllBy(32)));
    }
    return result & ((BigInt.one << numBits) - BigInt.one);
  }

  /// Generate unsigned random [LogicValue] based on [width] and [max] num.
  ///
  /// The random number can be mixed in invalid bits x and z by set
  /// [includeInvalidBits] to `true`. [max] can be used to set the maximum
  /// range of the generated number and its only accept runtimeType `int` and
  /// `BigInt`. [max] only work when [includeInvalidBits] is set to false
  /// else an exception will be thrown.
  LogicValue nextLogicValue({
    required int width,
    dynamic max,
    bool includeInvalidBits = false,
  }) {
    if (width == 0) {
      return LogicValue.empty;
    }

    if (max != null) {
      if (max is! int && max is! BigInt) {
        throw InvalidRandomLogicValueException(
            'max can be only runtimeType of int or BigInt.');
      }

      if (max is int && max == 0) {
        return LogicValue.ofInt(max, width);
      } else if (max is BigInt && max == BigInt.zero) {
        return LogicValue.ofBigInt(BigInt.zero, width);
      }

      if ((max is int && max < 0) || (max is BigInt && max < BigInt.zero)) {
        throw InvalidRandomLogicValueException('max cannot be less than 0');
      }
    }

    if (includeInvalidBits) {
      if (max != null) {
        throw InvalidRandomLogicValueException(
            'max does not work with invalid bits random number generation.');
      }

      final bitString = StringBuffer();
      for (var i = 0; i < width; i++) {
        bitString.write(const ['1', '0', 'x', 'z'][nextInt(4)]);
      }

      return LogicValue.ofString(bitString.toString());
    } else {
      if (width <= INT_BITS) {
        final ranNum = width <= 32
            ? LogicValue.ofInt(nextInt(oneSllBy(width)), width)
            : LogicValue.ofInt(_nextBigInt(numBits: width).toInt(), width);

        if (max == null || (max is BigInt && max.bitLength > INT_BITS)) {
          return ranNum;
        } else {
          return LogicValue.ofInt(
              ranNum.toInt() % (max is int ? max : (max as BigInt).toInt()),
              width);
        }
      } else {
        final ranNum = _nextBigInt(numBits: width);

        if (max == null ||
            (max is BigInt && ranNum.bitLength < max.bitLength)) {
          return LogicValue.ofBigInt(ranNum, width);
        } else {
          final maxBigInt = max is int ? BigInt.from(max) : max as BigInt;
          return LogicValue.ofBigInt(ranNum % maxBigInt, width);
        }
      }
    }
  }
}

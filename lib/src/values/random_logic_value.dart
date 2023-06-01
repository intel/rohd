/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// random_logic_value.dart
/// Random Logic Value generation extension.
///
/// 2023 May 18
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

part of values;

/// Allows random generation of [LogicValue] for [BigInt] and [int].
extension RandLogicValue on math.Random {
  /// Generate unsigned random [BigInt] value that consists of
  /// [numBits] bits.
  BigInt _nextBigInt({required int numBits}) {
    var result = BigInt.zero;
    for (var i = 0; i < numBits; i += 32) {
      result = (result << 32) | BigInt.from(nextInt(1 << 32));
    }
    return result & ((BigInt.one << numBits) - BigInt.one);
  }

  /// Generate unsigned random [LogicValue] based on [width] and [max] num.
  /// The random number can be mixed in invalid bits x and z by set
  /// [includeInvalidBits] to `true`. The [max] can be used to set the maximum
  /// range of the generated number. [max] only work when [includeInvalidBits]
  /// is set to false else an exception will be thrown.
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
            'invalid max parameter. Max can be only runtimeType of int'
            ' or BigInt.');
      }

      if (max is int && max == 0) {
        return LogicValue.ofInt(max, width);
      } else if (max is BigInt && max == BigInt.zero) {
        return LogicValue.ofBigInt(BigInt.zero, width);
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
      if (width <= LogicValue._INT_BITS) {
        LogicValue ranNum;
        if (width <= 32) {
          ranNum = LogicValue.ofInt(nextInt(1 << width), width);
        } else {
          ranNum = LogicValue.ofInt(_nextBigInt(numBits: width).toInt(), width);
        }

        if (max == null) {
          return ranNum;
        } else {
          if (max is BigInt) {
            if (max.isValidInt) {
              return LogicValue.ofInt(ranNum.toInt() % max.toInt(), width);
            } else {
              return ranNum;
            }
          } else {
            return LogicValue.ofInt(ranNum.toInt() % (max as int), width);
          }
        }
      } else {
        final ranNum = _nextBigInt(numBits: width);

        if (max == null ||
            (max is BigInt && ranNum.bitLength < max.bitLength)) {
          return LogicValue.ofBigInt(ranNum, width);
        } else {
          if (max is int) {
            max = BigInt.from(max);
            return LogicValue.ofBigInt(ranNum % max, width);
          } else if (max is BigInt) {
            return LogicValue.ofBigInt(ranNum % max, width);
          } else {
            throw InvalidRandomLogicValueException('max value is invalid.');
          }
        }
      }
    }
  }
}
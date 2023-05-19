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
extension RandLogicValue on Random {
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
  /// [includeInvalidBits] to `true`. [max] only work when [includeInvalidBits]
  /// is set to false and [width] is less than or equal to 64 bits.
  LogicValue nextLogicValue({
    required int width,
    int? max,
    bool includeInvalidBits = false,
  }) {
    if (width == 0) {
      throw RangeError('width size must be larger than 0');
    }

    if (includeInvalidBits) {
      final bitString = StringBuffer();
      for (var i = 0; i < width; i++) {
        bitString.write(const ['1', '0', 'x', 'z'][nextInt(4)]);
      }

      return LogicValue.ofString(bitString.toString());
    } else {
      if (width <= LogicValue._INT_BITS) {
        LogicValue ranNum;
        if (width < 32) {
          ranNum = LogicValue.ofInt(nextInt(1 << width), width);
        } else {
          ranNum = LogicValue.ofInt(_nextBigInt(numBits: width).toInt(), width);
        }

        return ranNum % (max ?? (1 << width) - 1);
      } else {
        return LogicValue.ofBigInt(_nextBigInt(numBits: width), width);
      }
    }
  }
}

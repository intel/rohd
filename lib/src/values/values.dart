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

extension RandLogicValue on Random {
  LogicValue nextLogicValue({required int max, int min = 0}) {
    final randInt = nextInt(max) + min;
    final width = randInt.bitLength;

    return LogicValue.ofInt(randInt, width);
  }

  BigInt nextBigInt({required int numBits}) {
    // Generate random Bit String
    var bitString = '1';
    for (var i = 1; i < numBits; i++) {
      bitString += nextInt(2).toString();
    }

    return BigInt.parse(bitString, radix: 2);
  }

  LogicValue nextBigIntLogicValue({required int numBits}) {
    final randBigInt = nextBigInt(numBits: numBits);
    final width = randBigInt.bitLength;

    return LogicValue.ofBigInt(randBigInt, width);
  }
}

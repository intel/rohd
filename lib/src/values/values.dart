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
  LogicValue nextLogicValueInt({required int max, int min = 0}) {
    final randInt = nextInt(max) + min;
    final width = randInt.bitLength;

    return LogicValue.ofInt(randInt, width);
  }

  BigInt nextBigInt({required int numBits}) {
    final bitString = StringBuffer('1');
    for (var i = 1; i < numBits; i++) {
      bitString.write(nextInt(2).toString());
    }

    return BigInt.parse(bitString.toString(), radix: 2);
  }

  LogicValue nextLogicValueBigInt({required int numBits}) {
    final randBigInt = nextBigInt(numBits: numBits);
    final width = randBigInt.bitLength;

    return LogicValue.ofBigInt(randBigInt, width);
  }
}

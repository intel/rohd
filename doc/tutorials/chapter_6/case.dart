// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// case.dart
//
// 2023 June 7
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/rohd.dart';

Case truthTableCase(
        Logic a, Logic b, Logic carryIn, Logic sum, Logic carryOut) =>
    Case(
      [a, b, carryIn].swizzle(),
      [
        CaseItem(Const(bin('000')), [sum < 0, carryOut < 0]),
        CaseItem(Const(bin('001')), [sum < 1, carryOut < 0]),
        CaseItem(Const(bin('010')), [sum < 1, carryOut < 0]),
        CaseItem(Const(bin('011')), [sum < 0, carryOut < 1]),
        CaseItem(Const(bin('100')), [sum < 1, carryOut < 1]),
        CaseItem(Const(bin('101')), [sum < 0, carryOut < 1]),
        CaseItem(Const(bin('110')), [sum < 0, carryOut < 1])
      ],
      defaultItem: [sum < 1, carryOut < 1],
    );

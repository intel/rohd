import 'package:rohd/rohd.dart';

If truthTableIf(Logic a, Logic b, Logic carryIn, Logic sum, Logic carryOut) =>
    If.block([
      Iff(a.eq(0) & b.eq(0) & carryIn.eq(0), [
        sum < 0,
        carryOut < 0,
      ]),
      ElseIf(a.eq(0) & b.eq(0) & carryIn.eq(1), [
        sum < 1,
        carryOut < 0,
      ]),
      ElseIf(a.eq(0) & b.eq(1) & carryIn.eq(0), [
        sum < 1,
        carryOut < 0,
      ]),
      ElseIf(a.eq(0) & b.eq(1) & carryIn.eq(1), [
        sum < 0,
        carryOut < 1,
      ]),
      ElseIf(a.eq(1) & b.eq(0) & carryIn.eq(0), [
        sum < 1,
        carryOut < 0,
      ]),
      ElseIf(a.eq(1) & b.eq(0) & carryIn.eq(1), [
        sum < 0,
        carryOut < 1,
      ]),
      ElseIf(a.eq(1) & b.eq(1) & carryIn.eq(0), [
        sum < 0,
        carryOut < 1,
      ]),
      // a = 1, b = 1, cin = 1
      Else([
        sum < 1,
        carryOut < 1,
      ])
    ]);

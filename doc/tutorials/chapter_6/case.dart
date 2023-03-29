import 'package:rohd/rohd.dart';

Case truthTableCase(
        Logic a, Logic b, Logic carryIn, Logic sum, Logic carryOut) =>
    Case(
      [a, b, carryIn].swizzle(),
      [
        CaseItem(Const(bin('000'), width: 3), [sum < 0, carryOut < 0]),
        CaseItem(Const(bin('001'), width: 3), [sum < 1, carryOut < 0]),
        CaseItem(Const(bin('010'), width: 3), [sum < 1, carryOut < 0]),
        CaseItem(Const(bin('011'), width: 3), [sum < 0, carryOut < 1]),
        CaseItem(Const(bin('100'), width: 3), [sum < 1, carryOut < 0]),
        CaseItem(Const(bin('101'), width: 3), [sum < 0, carryOut < 1]),
        CaseItem(Const(bin('110'), width: 3), [sum < 0, carryOut < 1])
      ],
      defaultItem: [sum < 1, carryOut < 1],
    );

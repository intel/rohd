---
title: "Simple logical, mathematical, and comparison operations"
permalink: /docs/logic-math-compare/
excerpt: "Simple logical, mathematical, and comparison operations"
last_modified_at: 2025-7-24
toc: true
---

Logical operations on signals are very similar to those in SystemVerilog.

```dart
a_bar     <=  ~a;      // not
a_and_b   <=  a & b;   // and
a_or_b    <=  a | b;   // or
a_xor_b   <=  a ^ b;   // xor
and_a     <=  a.and(); // unary and
or_a      <=  a.or();  // unary or
xor_a     <=  a.xor(); // unary xor
a_pow_b   <=  a.pow(b);// exponent
a_plus_b  <=  a + b;   // addition
a_sub_b   <=  a - b;   // subtraction
a_times_b <=  a * b;   // multiplication
a_div_b   <=  a / b;   // division
a_mod_b   <=  a % b;   // modulo
a_eq_b    <=  a.eq(b)  // equality              NOTE: == is for Object equality of Logic's
a_neq_b   <=  a.neq(b) // inequality            NOTE: != is for Object inequality of Logic's
a_lt_b    <=  a.lt(b)  // less than             NOTE: <  is for conditional assignment
a_lte_b   <=  a.lte(b) // less than or equal    NOTE: <= is for assignment
a_gt_b    <=  a.gt(b)  // greater than
a_gt_b    <=  (a > b)  // greater than          (alt) NOTE: careful with order of operations, > needs parentheses in this case
a_gte_b   <=  a.gte(b) // greater than or equal
a_gte_b   <=  (a >= b) // greater than or equal (alt) NOTE: careful with order of operations, >= needs parentheses in this case
answer    <=  mux(selectA, a, b) // answer = selectA ? a : b
```

For elaboration-time non-negative Dart `int` and `BigInt` values, the ROHD
extensions provide `log2Ceil` and `log2Floor` getters. A `LogicValue` instead
has a `log2Ceil` getter (also available as `clog2()`) that interprets the bits
as unsigned and returns a same-width `LogicValue`, or all `x` for an invalid
input. Both integer and value-domain ceiling operations return zero for zero.
These helpers are not synthesizable `Logic` operations.

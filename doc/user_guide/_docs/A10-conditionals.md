---
title: "Conditionals"
permalink: /docs/conditionals/
excerpt: "Conditionals"
last_modified_at: 2026-08-10
toc: true
---

ROHD supports a variety of [`Conditional`](https://intel.github.io/rohd/rohd/Conditional-class.html) type statements that always must fall within a type of `_Always` block, similar to SystemVerilog.  There are two types of `_Always` blocks: [`Sequential`](https://intel.github.io/rohd/rohd/Sequential-class.html) and [`Combinational`](https://intel.github.io/rohd/rohd/Combinational-class.html), which map to SystemVerilog's `always_ff` and `always_comb`, respectively.  `Combinational` takes a list of `Conditional` statements.  Different kinds of `Conditional` statement, such as `If`, may be composed of more `Conditional` statements.  You can create `Conditional` composition chains as deep as you like.

Conditional statements are executed imperatively and in order, just like the contents of `always` blocks in SystemVerilog.  `_Always` blocks in ROHD map 1-to-1 with SystemVerilog `always` statements when converted.

Assignments within an `_Always` should be executed conditionally, so use the `<` operator which creates a [`ConditionalAssign`](https://intel.github.io/rohd/rohd/ConditionalAssign-class.html) object instead of `<=`.  The right hand side a `ConditionalAssign` can be anything that can be `put` onto a `Logic`, which includes `int`s.  If you're looking to fill the width of something, use `Const` with the `fill = true`.

#### `If`

Below is an example of an [`If`](https://intel.github.io/rohd/rohd/If-class.html) statement in ROHD:

```dart
Combinational([
  If(a, then: [
      y < a,
      z < b,
      x < a & b,
      q < d,
  ], orElse: [ If(b, then: [
      y < b,
      z < a,
      q < 13,
  ], orElse: [
      y < 0,
      z < Const(1, width: 4, fill: true),
  ])])
]);
```

#### `If.block`

The `If.block` constructor makes syntax for long chains of if / else if / else chains nicer.  For example:

```dart
Sequential(clk, [
  If.block([
    // the first one must be Iff (yes, with 2 f's, to differentiate from If above)
    Iff(a & ~b, [
      c < 1,
      d < 0
    ]),
    ElseIf(b & ~a, [
      c < 1,
      d < 0
    ]),
    // have as many ElseIf's here as you want
    Else([
      c < 0,
      d < 1
    ])
  ])
]);
```

#### `Case` and `CaseZ`

ROHD supports [`Case`](https://intel.github.io/rohd/rohd/Case-class.html) and [`CaseZ`](https://intel.github.io/rohd/rohd/CaseZ-class.html) statements, including priority and unique flavors. These generate SystemVerilog `case` and `casez` statements, respectively. For example:

```dart
Combinational([
  Case([b,a].concat(), [
      CaseItem(Const(LogicValue.ofString('01')), [
        c < 1,
        d < 0
      ]),
      CaseItem(Const(LogicValue.ofString('10')), [
        c < 1,
        d < 0,
      ]),
    ], defaultItem: [
      c < 0,
      d < 1,
    ],
    conditionalType: ConditionalType.unique
  ),
  CaseZ([b,a].concat(),[
      CaseItem(Const(LogicValue.ofString('z1')), [
        e < 1,
      ])
    ], defaultItem: [
      e < 0,
    ],
    conditionalType: ConditionalType.priority
  )
]);
```

##### Four-state case matching

By default, ROHD functional simulation is pessimistic: a `Case` expression
containing X or Z drives the case outputs to X. An invalid case item encountered
while searching also drives the outputs to X. This can differ from generated
SystemVerilog, whose `case` statement compares all four states exactly.

Set `exactMatch: true` on `Case` to compare 0, 1, X, and Z bit-for-bit in
functional simulation. For example, an expression of `1x` matches an item of
`1x`, but not `1z` or `10`:

```dart
Combinational([
  Case(selector, [
    CaseItem(pattern, [hit < 1]),
  ], defaultItem: [
    hit < 0,
  ], exactMatch: true),
]);
```

The `cases` shorthand also accepts `exactMatch: true`:

```dart
final hit = cases(
  selector,
  {pattern: Const(1)},
  defaultValue: Const(0),
  exactMatch: true,
);
```

Use this mode when exact four-state identity is part of the intended behavior,
such as matching stored CAM tags. It is not wildcard matching: X and Z match
only the same state. The option affects functional simulation; both modes
generate the same SystemVerilog `case`. ROHD's generated SystemC is two-state
and cannot represent X or Z. `CaseZ` retains its existing wildcard and
pessimistic simulation behavior; it does not accept `exactMatch`.

The `cases` helper accepts enum members as keys when its selector is a compatible [`LogicEnum`](https://intel.github.io/rohd-website/docs/logic-enums/). It returns an ordinary `Logic`, so enum results must be supplied as explicitly mapped signals rather than bare Dart enum members.

Note that ROHD supports the 'z' syntax, not the '?' syntax (these are equivalent in SystemVerilog).

There is no support for an equivalent of `casex` from SystemVerilog, since it can easily cause unsynthesizeable code to be generated (see: <https://www.verilogpro.com/verilog-case-casez-casex/>).

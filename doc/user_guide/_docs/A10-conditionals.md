---
title: "Conditionals"
permalink: /docs/conditionals/
excerpt: "Conditionals"
last_modified_at: 2022-12-06
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

ROHD supports [`Case`](https://intel.github.io/rohd/rohd/Case-class.html) and [`CaseZ`](https://intel.github.io/rohd/rohd/CaseZ-class.html) statements, including priority and unique flavors, which are implemented in the same way as SystemVerilog.  For example:

```dart
Combinational([
  Case([b,a].swizzle(), [
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
  CaseZ([b,a].swizzle(),[
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

Note that ROHD supports the 'z' syntax, not the '?' syntax (these are equivalent in SystemVerilog).

There is no support for an equivalent of `casex` from SystemVerilog, since it can easily cause unsynthesizeable code to be generated (see: <https://www.verilogpro.com/verilog-case-casez-casex/>).

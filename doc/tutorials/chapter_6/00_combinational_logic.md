# Content

- [What is Combinational Logic?](#what-is-combinational-logic)
- [What is Conditionals?](#what-is-conditionals)
- [If, ElseIf, Else](#if-elseif-else)
  - [Start by declaring a conditional Block](#start-by-declaring-a-conditional-block)
  - [Add the condition inside the conditional block](#add-the-condition-inside-the-conditional-block)
- [Case, CaseZ](#case-casez)

## Learning Outcome

In this chapter:

- You will learn how to create a combinational logic that are equivalent to System Verilog `always_comb`. We will review on what is conditionals and how to use combinational condition function such as `If..Else` and `Case...CaseZ`.

## What is Combinational Logic?

There are two types of digital circuit, which are combinational logic and sequential logic. As for this chapter, we will look into combinational logic circuit.

A combinational circuit's outputs depends only on the current values of the inputs; in other words, it combines just the current input values to compute the output. For example, a logic gate is a combinational circuit.A circuit is combinational if it consists of interconnected circuit elements such that:

- Every circuit element is itself combinational.
- Every node of the circuits is either designated as an input to the circuit or connects to exactly one output terminal of a circuit element.
- The circuit contains no cyclic paths: every path through the circuit visits each circuit node at most once.

## What is Conditionals?

In ROHD, `Conditional` type statement must always written within a type of `_Always` block, similar to System Verilog. There are two type of `_Always` blocks: `Sequential` and `Combinational`, which map to System Verilog's `always_ff` and `always_comb`, respectively.

```dart
// Example of always_comb
Combinational([
  // Conditionals written inside here...
]);
```

`Combinational` Block takes a list of `Conditional` statements. Different kinds of `Conditional` statement, such as `If`, may be composed of more `Conditional` statements. You can create `Conditional` composition chains as deep as you like.

Conditional statements are executed imperatively and in order, just like the contents of `always` blocks in SystemVerilog. `_Always` blocks in ROHD map 1-to-1 with SystemVerilog `always` statements when converted.

Assignments within an `_Always` should be executed conditionally, so use the `<` operator which creates a `ConditionalAssign` object instead of `<=`. The right hand side a `ConditionalAssign` can be anything that can be `put` onto a `Logic`, which includes `int`s. If you're looking to fill the width of something, use `Const` with the `fill = true`.

Example below shows the example of `Combinational` with `Logic` and `ConditionalAssign`.

```dart
final and1 = carryIn & (a ^ b);
final and2 = b & a;

Combinational([
    // notice that `<` in used instead of `<=` inside _Always
    sum < (a ^ b) ^ carryIn,
    carryOut < and1 | and2,
]);
```

The most important part that you have to notice here is the assignment operator in `Combinational` Block is different from common dart operator. So, a few operators that being use commonly are:

- `.eq()` function map to `==`
- `.lt()` function map to `<`
- `.lte()` function map to `<=`
- `(>)` function map to `>`
- `(>=)` function map to `>=`

## If, ElseIf, Else

Alright, now we know how the operator in ROHD. we can dive into the `IF...ELSE` in ROHD. In dart, `if...else` is used as a conditional for hardware generation, we can think of it as `if` condition A filled, then generate this pieces of hardware `else` generate this pieces of hardware. While in ROHD, `IF...ELSE` is conditionally assignment which assign signal to a port, which we can think something like `IF` Logic signal `A` is present, `THEN` assign output port `B` to `A`.

In today tutorial, we will review how to assign value to PORT using ROHD `IF...ELSE` conditionals. Let start by understanding ROHD `IF...ELSE` conditionals. There are several ways of using `If...Else` in ROHD, but the most prefferable way is using `IFBlock` which is more readable and clean.

// TODO: try to explain based on the IF ELSE documentation structure, clearer.
### Start by declaring a conditional Block

`IfBlock([])`: Represents a chain of blocks of code to be conditionally executed, like `if/else...if/else`. From the statement, we know that we have to wrap our `If...Else` using this function.

```dart
IfBlock([
  // your if else start here
]);
```

### Add the condition inside the conditional Block

`Iff(condition, then: [])`: `Iff` Statement, if condition is matched, then execute the `then` condition.

```dart
// template
IfBlock([
  Iff(condition, then: [
    // You can wrap condition here
  ]),
]); // IfBlock

// example
IfBlock([
  Iff(a.eq(0), then: [
    sum < 0    
  ]),
]); // IfBlock
```

`ElseIf(condition, then: [])`: `ElseIf` Statement, if the condition in `Iff` is not matched, its will skip and look for next condition in `ElseIf` condition.

```dart
// template
IfBlock([
  Iff(condition, then: []), // If statement
  ElseIf(condition, then: []) // Else If Statement
]); // IfBlock

// example
IfBlock([
  Iff(a.eq(0), then: [
    sum < 1
  ]), // If statement
  ElseIf(b.eq(0), then: [
    sum < 0
  ]) // Else If Statement
]); // IfBlock
```

`Else([])`: `Else` statement, execute the `Else` all the `ElseIf` conditions if are not matched.

```dart
IfBlock([
  Iff(condition, then: []), // If statement
  ElseIf(condition, then: []), // Else If Statement
  Else([]) // execute this
]); // IfBlock

// example
IfBlock([
  Iff(a.eq(0), then: [
    sum < 0
  ]), // If statement
  ElseIf(b.eq(0), then: [
    sum < 1
  ]), // Else If Statement
  Else([
    sum < 0>
  ]) // execute this
]); // IfBlock
```

Alright, the syntax is quite easy. You can always come back to this page whenever you are confuse. Let see how we can implement our FullAdder using `If` and `Else` conditionals.

Let look into the Truth Table of the full-adder.

// TODO: Give step by step explanation on how to add the adder.

|A|B|Cin|SUM (S)|CARRY (Cout)|
|---|---|---|---|--- |
|0|0|0|0|0|
|0|0|1|1|0|
|0|1|0|1|0|
|0|1|1|0|1|
|1|0|0|1|0|
|1|0|1|0|1|
|1|1|0|0|1|
|1|1|1|1|1|

Well, maybe you already have the idea. Yes, we are going to implment this truth table using `If...Else` statement. The code below show how we convert our Logic from previous tutorial.

```dart
    // Use Combinational block
    Combinational([
      IfBlock([
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
      ]),
    ]);
```

Tadaa! This is the implementation of the `If...Else` statement. If you run your test, its should still work the same. That the reason we have unit test.

So, how about `switch...case`? Well, its pretty much the same. Let see the syntax in `Case` and `CaseZ`.

## Case, CaseZ

ROHD supports Case and CaseZ statements, including priority and unique flavors, which are implemented in the same way as SystemVerilog. For example:

### Start by declaring a Case

`Case([])`: In `Case`, whenever an item in [items] matches [expression], it will be executed. If none of [items] match, then [defaultItem] is executed.

```dart
Case(
  Logic expression,
  List<CaseItem> items, {
  List<Conditional>? defaultItem,
})
```

### Add Expressions

`Logic expression`: The expression of `Case` are in the form of logic, so if you have more than one `signal`, you might want to use `swizzle()` to combine as one.

```dart
Case(
  // swizzle signal a and b as expression
  [b, a].swizzle(),
)
```

### Add Case Items

`CaseItem(Logic value, List<Conditional> then)`: `CaseItem` accepts `Logic` value as condition, if the condition matched; then the `then` condition will be executed. The `then` condition is added as a list to be driven during the Simulation.

```dart
List<CaseItem>
```

Remember that, the `CaseItem` should be in the List of the `List<CaseItem>` reside in `Case`.

```dart
Case(
  // swizzle signal a and b as expression
  [b, a].swizzle(),
  [
    // Case Items here
    CaseItem(Const(LogicValue.ofString('01')), [
      c < 1,
      d < 0
    ]),
  ], {
  List<Conditional>? defaultItem,
})
```

### Add default Items

`List<Conditional>? defaultItem` : `defaultItem` conditions will be executed if none of the expression matched.

```dart
Case(
  // swizzle signal a and b as expression
  [b, a].swizzle(),
  [
    // Case Items here
    CaseItem(Const(LogicValue.ofString('01')), [
      c < 1,
      d < 0
    ]),
  ], {
  List<Conditional>? defaultItem,
})
```

### Encapsulate Case into a Combinational

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
    conditionalType: ConditionalType.Unique
  ),
  CaseZ([b,a].swizzle(),[
      CaseItem(Const(LogicValue.ofString('z1')), [
        e < 1,
      ])
    ], defaultItem: [
      e < 0,
    ],
    conditionalType: ConditionalType.Priority
  )
]);
```

Yes, that it for `Case`, `CaseZ` in ROHD.

// TODO: Make the question more clear.
Exercise:

1. Code Case and CaseZ in ROHD for full adder.

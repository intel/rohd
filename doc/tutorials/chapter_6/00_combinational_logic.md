# Content

- [What is Combinational Logic?](#what-is-combinational-logic)
- [What is Conditionals?](#what-is-conditionals)
- [If, ElseIf, Else](#if-elseif-else)
  - [Start by declaring a conditional Block](#start-by-declaring-a-conditional-block)
  - [Add the condition inside the conditional block](#add-the-condition-inside-the-conditional-block)
- [Case](#case)
  - [Start by declaring a case](#start-by-declaring-a-case)
  - [Add Expressions](#add-expressions)
  - [Add Case Items](#add-case-items)
  - [Add Default Items](#add-default-items)
  - [Encapsulate case into a Combinational](#encapsulate-case-into-a-combinational)
- [Exercises](#exercises)

## Learning Outcome

In this chapter:

- You will learn how to create a combinational logic that are equivalent to System Verilog `always_comb`. We will review on what is conditionals and how to use combinational condition function such as `If..Else` and `Case`.

## What is Combinational Logic?

There are two types of digital circuit, which are combinational logic and sequential logic. As for this chapter, we will look into combinational logic circuit.

A combinational circuit is a type of circuit where the outputs are determined solely by the current inputs. It doesn't store any information or have memory. Each output is calculated based on the current values of the inputs using logical operations. For example, a logic gate is a basic building block of a combinational circuit.

Some criteria to identify a combinational circuit include: each circuit element being combinational, absence of cyclic paths or feedback loops, and lack of memory elements. It's important to note that these criteria are not exhaustive, and there may be additional criteria to consider.

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

Alright, now we know how the operator in ROHD. we can dive into the `If...Else` in ROHD. In dart, `if...else` is used as a conditional for hardware generation, we can think of it as `if` condition A filled, then generate this pieces of hardware `else` generate that pieces of hardware. While in ROHD, `If...Else` is conditionally assignment which assign signal to a port, which we can think something like `If` Logic signal `A` is high, `Then` assign output port `B` to `A`.

In today tutorial, we will review how to assign value to PORT using ROHD `If...Else` conditionals. Let start by understanding ROHD `If...Else` conditionals. There are several ways of using `If...Else` in ROHD, but the most preferable way is using `If.block` which is more readable and clean.

*Note: `If...Else` and `Case` in ROHD is written with the first letter capitalized to differentiate from the built-in dart keywords and functionality.*

### Start by declaring a conditional Block

`If.block([])`: Represents a chain of blocks of code to be conditionally executed, like if/else...if/else in dart.

```dart
If.block([
  // your if else inside here
]);
```

### Add the condition inside the conditional Block

`Iff(condition, then: [])`: `Iff` Statement, if condition is matched, then execute the `then` condition.

```dart
// template
If.block([
  Iff(condition, then: [
    // You can wrap condition here
  ]),
]); // If.block

// example
If.block([
  Iff(a.eq(0), then: [
    sum < 0    
  ]),
]); // If.block
```

`ElseIf(condition, then: [])`: `ElseIf` Statement, if the condition in `Iff` is not matched, its will skip and look for next condition in `ElseIf` condition, then execute the `then`.

```dart
// template
If.block([
  Iff(condition, then: []), // If statement
  ElseIf(condition, then: []) // Else If Statement
]); // If.block

// example
If.block([
  Iff(a.eq(0), then: [
    sum < 1
  ]), // If statement
  ElseIf(b.eq(0), then: [
    sum < 0
  ]) // Else If Statement
]); // If.block
```

`Else([])`: `Else` statement, execute the `Else` all the `ElseIf` conditions if are not matched.

```dart
If.block([
  Iff(condition, then: []), // If statement
  ElseIf(condition, then: []), // Else If Statement
  Else([]) // execute this
]); // If.block

// example
If.block([
  Iff(a.eq(0), then: [
    sum < 0
  ]), // If statement
  ElseIf(b.eq(0), then: [
    sum < 1
  ]), // Else If Statement
  Else([
    a < 1
  ]) // execute this
]); // If.block
```

Alright, the syntax is quite easy. You can always come back to this page whenever you are confuse. Let see how we can implement our FullAdder using `If` and `Else` conditionals.

Now, let create a truth table for the full-adder we created in last chapter. The table below shows the truth table for the full-adder.

|A|B|Cin|SUM (S)|CARRY (Cout)|
|---|---|---|---|---|
|0|0|0|0|0|
|0|0|1|1|0|
|0|1|0|1|0|
|0|1|1|0|1|
|1|0|0|1|0|
|1|0|1|0|1|
|1|1|0|0|1|
|1|1|1|1|1|

Well, maybe you already have the idea. Yes, we are going to implement this truth table using `If...Else` statement. The code below show how we convert our Logic from previous tutorial.

```dart
    // Use Combinational block
    Combinational([
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
      ]),
    ]);
```

So, to add our `if...else` to the as combinational logic. We have to wrap with `Combinational` and add it into the FullAdder module like below.

```dart
class FullAdder extends Module {
  final fullAdderresult = FullAdderResult();

  // Constructor
  FullAdder({
    required Logic a,
    required Logic b,
    required Logic carryIn,
    super.name = 'full_adder',
  }) {
    // Declare Input Node
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    carryIn = addInput('carry_in', carryIn, width: carryIn.width);

    // Declare Output Node
    final carryOut = addOutput('carry_out');
    final sum = addOutput('sum');

    // Use Combinational block
    Combinational([
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
      ]),
    ]);

    fullAdderresult.sum <= output('sum');
    fullAdderresult.cOut <= output('carry_out');
  }
}
```

Tadaa! This is the implementation of the `If...Else` statement.  You can find the executable version of code at [combinational_logic.dart](combinational_logic.dart). If you run your test, its should still work the same.

So, how about `switch...case`? Well, its pretty much the same. Let see the syntax in `Case`.

## Case

ROHD supports Case statements, including priority and unique flavors, which are implemented in the same way as SystemVerilog. For example:

### Start by declaring a Case

`Case([])`: In a Case statement, each item in the `items` list is checked against the `expression`. If a matching item is found, its associated code block is executed. If none of the items match, the code block associated with the [defaultItem] is executed instead. This allows you to handle different scenarios in your program based on the value of the [expression].

```dart
Case(
  Logic expression,
  List<CaseItem> items, {
  List<Conditional>? defaultItem,
})
```

### Add Expressions

`Logic expression`: `Case` expressions are made up of logical values. If you have multiple signals that you want to combine into one expression, you can use the `swizzle()` function. This function allows you to create a new expression by selecting individual elements from existing expressions and combining them in a specified order. By using `swizzle()`, you can create complex expressions that represent the behavior of your circuit.

```dart
Case(
  // swizzle signal a and b as expression
  [b, a].swizzle(),
)
```

### Add Case Items

`CaseItem(Logic value, List<Conditional> then)`: The `CaseItem` function takes a `Logic` value as a condition. If the condition is met, the `then` condition will be executed. The `then` condition is a list of actions to be carried out during the simulation.

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
  )
]);
```

Yes, that it for `Case` in ROHD.

ROHD also support `CaseZ` statements with the `z` syntax, not the `?` syntax (these are quivalent in SystemVerilog). There is no support for an equivalent of `casex` from SystemVerilog, since it can easily cause unsynthesizable code to be generated [see: https://www.verilogpro.com/verilog-case-casez-casex/](https://www.verilogpro.com/verilog-case-casez-casex/).

Below is the example of using `CaseZ`.

```dart
CaseZ([b,a].swizzle(),[
    CaseItem(Const(LogicValue.ofString('z1')), [
      e < 1,
    ])
  ], defaultItem: [
    e < 0,
  ],
  conditionalType: ConditionalType.Priority
)
```

## Exercises

1. In the file [case.dart](case.dart), a `Case` Conditionals is created for full adder truth table but unfortunately there are some bugs on the code. Can you try to fix the bug? A unit test already created, Try your best to make the test work. You might want to refer to [Chapter 2](../chapter_2/00_basic_logic.md) for  this question.

    - Answer to this exercise can be found at [answers/exercise_1_case_answer.dart](./answers/exercise_1_case_answer.dart).

2. Add combinational logic to `FullSubtractor` you created in previous exercise (Use Case Conditionals).

    - Answer to this exercise can be found at [answers/exercise_2_n_bit_subtractor.dart](./answers/exercise_2_n_bit_subtractor.dart).

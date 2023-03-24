# Combinational Logic

In the previous section, we had learn how to implement a ROHD module. In this section, we will learn how combinational logic is being used in ROHD. In this tutorial, let see how we can use `if...else` to conditionally assign signals to hardware. Let us zoom in to the Combinational Block of the full adder we implemented from the last module. 

```dart
final and1 = carryIn & (a ^ b);
final and2 = b & a;
Combinational([
    sum < (a ^ b) ^ carryIn,
    carryOut < and1 | and2,
]);
```

Well, that the part of the full adder logic that we implmented from last tutorials. Today, we are going to implemented the same full adder logic using just `if...else` statement in ROHD. Let start by looking into ROHD conditionals. From the [API documentation](https://intel.github.io/rohd/docs/logic-math-compare/), conditionals in ROHD are defined in:

```dart
_bar     <=  ~a;      // not
a_and_b   <=  a & b;   // and
a_or_b    <=  a | b;   // or
a_xor_b   <=  a ^ b;   // xor
and_a     <=  a.and(); // unary and
or_a      <=  a.or();  // unary or
xor_a     <=  a.xor(); // unary xor
a_plus_b  <=  a + b;   // addition
a_sub_b   <=  a - b;   // subtraction
a_times_b <=  a * b;   // multiplication
a_div_b   <=  a / b;   // division
a_mod_b   <=  a % b;   // modulo
a_eq_b    <=  a.eq(b)  // equality              NOTE: == is for Object equality of Logic's
a_lt_b    <=  a.lt(b)  // less than             NOTE: <  is for conditional assignment
a_lte_b   <=  a.lte(b) // less than or equal    NOTE: <= is for assignment
a_gt_b    <=  (a > b)  // greater than          NOTE: careful with order of operations, > needs parentheses in this case
a_gte_b   <=  (a >= b) // greater than or equal NOTE: careful with order of operations, >= needs parentheses in this case
answer    <=  mux(selectA, a, b) // answer = selectA ? a : b
```

The most important part that we notice here is the assignment operator in Combinational Block is different from Logic operator. So, a few operators that being use commonly are 

- `.eq()` function map to `==` 
- `.lt()` function map to `<`
- `.lte()` function map to `<=`
- `(>)` function map to `>`
- `(>=)` function map to `>=`

Alright, now we know how the operator in ROHD. we can dive into the `IF...ELSE` in ROHD. In dart, `IF...ELSE` is used as a conditional for hardware generation, we can think of it as `IF` condition A filled, then generate this pieces of hardware `ELSE` generate this pieces of hardware. While in ROHD, `IF...ELSE` is conditionally assignment which assign signal to a port, which we can think something like `IF` Logic signal A is present, `THEN` assign output port B to A. 

In today tutorial, we will review how to assign value to PORT using ROHD `IF...ELSE` signals. Let start by understanding ROHD `IF...ELSE` conditionals. There are several ways of using `If...Else` in ROHD, but the most prefferable way is using `IFBlock` which is more readable and clean.

1. `IfBlock([])`: Represents a chain of blocks of code to be conditionally executed, like if/else if/else. From the statement, we know that wehave to wrap our If...Else using this function.

```dart
IfBlock([]);
```

2. `Iff(condition, then: [])`: If Statement

```dart
IfBlock([
    Iff(condition, then: []),
]); // IfBlock
```

3. `ElseIf(condition, then: [])`: ElseIf Statement

```dart
IfBlock([
    Iff(condition, then: []), // If statement
    ElseIf(condition, then: []) // Else If Statement
]); // IfBlock
```

4. `Else([])`: Else statement

```dart
IfBlock([
    Iff(condition, then: []), // If statement
    ElseIf(condition, then: []), // Else If Statement
    Else([])
]); // IfBlock
```

Alright, the syntax is quite easy. You can always come back to this page whenever you are confuse. Let see how we can implement our FullAdder using If and Else.

## Full-Adder

Let look into the Truth Table of the full-adder.

|A      |	B	| Cin	| SUM (S)	|CARRY (Cout) |
| ---   |  ---	|  ---	|    ---	|    ---      |
|0      |	0	| 0	    | 0	        |0            |
|0      |	0	| 1	    | 1	        |0            |
|0      |	1	| 0	    | 1	        |0            |
|0      |	1	| 1	    | 0	        |1            |
|1      |	0	| 0	    | 1	        |0            |
|1      |	0	| 1	    | 0	        |1            |
|1      |	1	| 0	    | 0	        |1            |
|1      |	1	| 1	    | 1	        |1            |

Well, maybe you already have the idea. Yes, we are going to implment this truth table using If...Else statement. The code below show how we convert our Logic from previous tutorial.

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

Tadaa! This is the implementation of the If...Else statement. If you run your test, its should still work the same. That the reason we have unit test.

So, how about switch...case? Well, its pretty much the same. Let see the syntax in Case and CaseZ. 
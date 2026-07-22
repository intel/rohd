---
title: "Constants"
permalink: /docs/constant/
excerpt: "Constants"
last_modified_at: 2026-07-14
toc: true
---

Constants can often be inferred by ROHD automatically, but can also be explicitly defined using [`Const`](https://intel.github.io/rohd/rohd/Const-class.html), which extends `Logic`.

```dart
// a 16 bit constant with value 5
var x = Const(5, width: 16);
```

## Preferred radix

The optional `preferredRadix` controls how a `Const` is displayed in generated outputs. Supported radices are binary (2), octal (8), decimal (10), and hexadecimal (16). The radix only affects formatting, not the value of the constant.

```dart
var binary = Const(42, width: 8, preferredRadix: 2);     // 8'b101010
var octal = Const(42, width: 8, preferredRadix: 8);      // 8'o52
var decimal = Const(42, width: 8, preferredRadix: 10);   // 8'd42
var hexadecimal = Const(42, width: 8, preferredRadix: 16); // 8'h2a
```

Constants containing `x` or `z` may fall back to binary so all bit states can be represented.

## Binary integer conversion

There is a convenience function for converting binary to an integer:

```dart
// this is equivalent to and shorter than int.parse('010101', radix: 2)
// you can put underscores to help with readability, they are ignored
bin('01_0101')
```

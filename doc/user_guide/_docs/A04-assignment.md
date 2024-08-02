---
title: "Assignment"
permalink: /docs/assignment/
excerpt: "Assignment"
last_modified_at: 2024-08-02
toc: true
---

To assign one signal to the value of another signal, use the `<=` operator.  This is a hardware synthesizable assignment connecting two wires together.

```dart
var a = Logic(), b = Logic();

// assign `a` to always have the same value as `b`
a <= b;
```

It is also possible to do a partial assignment to a signal using `assignSubset`.

```dart
var a = Logic(width: 3), b = Logic(width: 2);

// assign the bottom two bits of `a` to have the same value as `b`
a.assignSubset(b.elements);

// assign the upper bit (index 2) of `a` to be 0
a.assignSubset([Const(0)], 2);
```

Note that using `assignSubset` on a `Logic` (as opposed to an array or struct) will bit-blast a pre-driver into a `LogicArray`. If you're assigning many bits that are already collected as a single `Logic`, consider using a `swizzle` to get better simulation performance and cleaner generated outputs.

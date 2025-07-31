---
title: "Assignment"
permalink: /docs/assignment/
excerpt: "Assignment"
last_modified_at: 2025-7-24
toc: true
---

To assign one signal to the value of another signal, use the `<=` operator.  This is a hardware synthesizable assignment connecting two wires together.

```dart
var a = Logic(), b = Logic();

// assign `a` to always have the same value as `b`
a <= b;

// or, equivalently, you can use the `gets` function, which may be more convenient in some situations
a.gets(b);
```

It is also possible to do a partial assignment to a signal using `assignSubset`.

```dart
var a = Logic(width: 3), b = Logic(width: 2);

// assign the bottom two bits of `a` to have the same value as `b`
a.assignSubset(b.elements);

// assign the upper bit (index 2) of `a` to be 0
a.assignSubset([Const(0)], 2);
```

If you're assigning groups of bits that are already collected as a single `Logic`, consider using a [`swizzle`](https://intel.github.io/rohd-website/docs/bus-range-swizzling/).

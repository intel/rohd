---
title: "Bus ranges and swizzling"
permalink: /docs/bus-range-swizzling/
excerpt: "Bus ranges and swizzling"
last_modified_at: 2022-12-06
toc: true
---

Multi-bit busses can be accessed by single bits and ranges or composed from multiple other signals.  Slicing, swizzling, etc. are also accessible on `LogicValue`s.

```dart
var a = Logic(width:8),
    b = Logic(width:3),
    c = Const(7, width:5),
    d = Logic(),
    e = Logic(width: 9);


// assign b to the bottom 3 bits of a
b <= a.slice(2,0);

// assign d to the top bit of a
d <= a[7];

// construct e by swizzling bits from b, c, and d
// here, the MSB is on the left, LSB is on the right
e <= [d, c, b].swizzle();

// alternatively, do a reverse swizzle 
// (useful for lists where 0-index is actually the 0th element)
//
// here, the LSB is on the left, the MSB is on the right
e <= [b, c, d].rswizzle();
```

ROHD does not support assignment to a subset of a bus.  That is, you *cannot* do something like `e[3] <= d`.  Instead, you can use the `withSet` function to get a copy with that subset of the bus assigned to something else.  This applies for both `Logic` and `LogicValue`.  For example:

```dart
// reassign the variable `e` to a new `Logic` where bit 3 is set to `d`
e = e.withSet(3, d);
```

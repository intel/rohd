---
title: "Bus ranges and concatenation"
permalink: /docs/bus-range-concatenation/
excerpt: "Bus ranges and concatenation"
last_modified_at: 2026-11-3
toc: true
---

Multi-bit buses can be accessed by single bits and ranges or composed from
multiple other signals. Slicing and concatenation are also accessible on
`LogicValue`s.

```dart
var a = Logic(width:8),
    b = Logic(width:3),
    c = Const(7, width:5),
    d = Logic(),
    e = Logic(width: 9);


// assign b to be driven by the bottom 3 bits of a
b <= a.slice(2,0);

// assign d to be driven by the top bit of a
d <= a[7];

// concatenate bits from b, c, and d
// here, the MSB is on the left, LSB is on the right
e <= [d, c, b].concat();

// alternatively, concatenate with the first list element as the LSB
// (useful for lists where 0-index is actually the 0th element)
//
// here, the LSB is on the left, the MSB is on the right
e <= [b, c, d].rconcat();
```

`concat` is equivalent to SystemVerilog's `{}` notation: list index 0
contributes the most significant bits. `rconcat` reverses that convention, so
list index 0 contributes the least significant bits. The existing `concat`
and `rconcat` names remain available as aliases during the migration.

## Splitting buses

Use `split` to partition a `Logic` or `LogicValue` into LSB-first chunks. The
chunk widths must be non-negative and sum exactly to the source width:

```dart
final packet = Logic(width: 16);
final fields = packet.split([4, 8, 4]);

final lowNibble = fields[0];
final payload = fields[1];
final highNibble = fields[2];
```

The same API works for values:

```dart
final value = LogicValue.ofString('11010110');
final chunks = value.split([2, 3, 3]);
// chunks: [2'b10, 3'b101, 3'b110]
```

ROHD does not support assignment to a subset of a bus.  That is, you *cannot* do something like `e[3] <= d`.  Instead, you can use the `withSet` function to get a copy with that subset of the bus assigned to something else.  This applies for both `Logic` and `LogicValue`.  For example:

```dart
// reassign the variable `e` to a new `Logic` where bit 3 is set to `d`
e = e.withSet(3, d);
```

---
title: "Non-synthesizable signal deposition"
permalink: /docs/non-synthesizable-signal/
excerpt: "Non-synthesizable signal deposition"
last_modified_at: 2022-12-06
toc: true
---

For testbench code or other non-synthesizable code, you can use `put` or `inject` on any `Logic` to deposit a value on the signal.  The two functions have similar behavior, but `inject` is shorthand for calling `put` inside of `Simulator.injectAction`, which allows the deposited change to propogate within the same `Simulator` tick.  Generally, you will want to use `inject` for testbench interaction with a design if it has any sequential elements.

```dart
var a = Logic(), b = Logic(width:4);

// you can put an int directly on a signal
a.put(0);
b.inject(0xf);

// you can also put a `LogicValue` onto a signal
a.inject(LogicValue.x);
```

Note: changing a value directly with `put()` will propogate the value, but it will not trigger flip-flop edge detection or cosim interaction.

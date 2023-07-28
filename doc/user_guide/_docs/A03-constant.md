---
title: "Constants"
permalink: /docs/constant/
excerpt: "Constants"
last_modified_at: 2022-12-06
toc: true
---

Constants can often be inferred by ROHD automatically, but can also be explicitly defined using [`Const`](https://intel.github.io/rohd/rohd/Const-class.html), which extends `Logic`.

```dart
// a 16 bit constant with value 5
var x = Const(5, width:16);
```

There is a convenience function for converting binary to an integer:

```dart
// this is equvialent to and shorter than int.parse('010101', radix:2)
// you can put underscores to help with readability, they are ignored
bin('01_0101')
```

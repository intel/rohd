---
title: "Shift Operations"
permalink: /docs/shift-operations/
excerpt: "Shift Operations"
last_modified_at: 2022-12-06
toc: true
---

### Shift Operations

Dart has [implemented the triple shift](https://github.com/dart-lang/language/blob/master/accepted/2.14/triple-shift-operator/feature-specification.md) operator ``(>>>)`` in the opposite way as is [implemented in SystemVerilog](https://www.nandland.com/verilog/examples/example-shift-operator-verilog.html).  That is to say in Dart, ``>>>`` means *logical* shift right (fill with 0's), and ``>>`` means *arithmetic* shift right (maintaining sign).  ROHD keeps consistency with Dart's implementation to avoid introducing confusion within Dart code you write (whether ROHD or plain Dart).

```dart
a << b    // logical shift left
a >> b    // arithmetic shift right
a >>> b   // logical shift right
```

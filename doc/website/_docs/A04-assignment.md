---
title: "Assignment"
permalink: /docs/assignment/
excerpt: "Assignment"
last_modified_at: 2022-12-06T08:48:05-04:00
toc: true
---

### Assignment
To assign one signal to the value of another signal, use the `<=` operator.  This is a hardware synthesizable assignment connecting two wires together.
```dart
var a = Logic(), b = Logic();
// assign a to always have the same value as b
a <= b;
```
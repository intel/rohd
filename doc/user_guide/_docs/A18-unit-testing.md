---
title: "Unit Testing"
permalink: /docs/unit-test/
excerpt: "Unit Testing"
last_modified_at: 2024-06-11
toc: true
---

Dart has a great unit testing package available on pub.dev: <https://pub.dev/packages/test>

The ROHD package has a great set of examples of how to write unit tests for ROHD `Module`s in the `test/` directory.

Note that when unit testing with ROHD, it is important to reset the `Simulator` with `Simulator.reset()` between tests.  For example, you could include something like the following so that the `Simulator` is always reset at the end of each of your tests:

```dart
void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('my first test', () async {
    ...
```

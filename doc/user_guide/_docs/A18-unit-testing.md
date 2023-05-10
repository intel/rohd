---
title: "Unit Testing"
permalink: /docs/unit-test/
excerpt: "Unit Testing"
last_modified_at: 2022-12-06
toc: true
---

## Unit Testing

Dart has a great unit testing package available on pub.dev: [https://pub.dev/packages/test](https://pub.dev/packages/test)

The ROHD package has a great set of examples of how to write unit tests for ROHD `Module`s in the test/ directory.

Note that when unit testing with ROHD, it is important to reset the `Simulator` with `Simulator.reset()`.

---
title: "Sequentials"
permalink: /docs/sequentials/
excerpt: "Sequentials"
last_modified_at: 2022-12-06
toc: true
---

ROHD has a basic [`FlipFlop`](https://intel.github.io/rohd/rohd/FlipFlop-class.html) module that can be used as a flip flop.  You can use the shorthand [`flop`](https://intel.github.io/rohd/rohd/flop.html) to construct a `FlipFlop`.  For more complex sequential logic, use the `Sequential` block described in the Conditionals section.

Dart doesn't have a notion of certain signals being "clocks" vs. "not clocks".  You can use any signal as a clock input to sequential logic, and have as many clocks of as many frequencies as you want.

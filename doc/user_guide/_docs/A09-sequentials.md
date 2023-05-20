---
title: "Sequentials"
permalink: /docs/sequentials/
excerpt: "Sequentials"
last_modified_at: 2022-12-06
toc: true
---

### Sequentials

ROHD has a basic [`FlipFlop`]({{ site.baseurl }}api/rohd/FlipFlop-class.html) module that can be used as a flip flop.  For more complex sequential logic, use the `Sequential` block described in the Conditionals section.

Dart doesn't have a notion of certain signals being "clocks" vs. "not clocks".  You can use any signal as a clock input to sequential logic, and have as many clocks of as many frequencies as you want.

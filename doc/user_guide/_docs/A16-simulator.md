---
title: "ROHD Simulator"
permalink: /docs/simulator/
excerpt: "ROHD Simulator"
last_modified_at: 2022-12-06
toc: true
---

The ROHD simulator is a static class accessible as [`Simulator`](https://intel.github.io/rohd/rohd/Simulator-class.html) which implements a simple event-based simulator.  All `Logic`s in Dart have `glitch` events which propogate values to connected `Logic`s downstream.  In this way, ROHD propogates values across the entire graph representation of the hardware (without any `Simulator` involvement required).  The simulator has a concept of (unitless) time, and arbitrary Dart functions can be registered to occur at arbitraty times in the simulator.  Asking the simulator to run causes it to iterate through all registered timestamps and execute the functions in chronological order.  When these functions deposit signals on `Logic`s, it propogates values across the hardware.  The simulator has a number of events surrounding execution of a timestamp tick so that things like `FlipFlop`s can know when clocks and signals are glitch-free.

- To register a function at an arbitraty timestamp, use `Simulator.registerAction`
- To set a maximum simulation time, use `Simulator.setMaxSimTime`
- To immediately end the simulation at the end of the current timestamp, use `Simulator.endSimulation`
- To run just the next timestamp, use `Simulator.tick`
- To run simulator ticks until completion, use `Simulator.run`
- To reset the simulator, use `Simulator.reset`
  - Note that this only resets the `Simulator` and not any `Module`s or `Logic` values
- To add an action to the Simulator in the *current* timestep, use `Simulator.injectAction`.

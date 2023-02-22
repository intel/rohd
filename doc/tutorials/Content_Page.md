# Content Page

## Chapter 1: Getting Started

- [Introduction to ROHD](./Chapter_1/00-Introduction_to_ROHD.md)
  - [What is ROHD?](./Chapter_1/00-Introduction_to_ROHD.md)
  - [Challenges in Hardware Industry](./Chapter_1/00-Introduction_to_ROHD.md#challenges-in-hardware-industry)
  - [Benefits of Dart for hardware development](./Chapter_1/00-Introduction_to_ROHD.md#benefits-of-dart-for-hardware-development)
  - [Example of ROHD with Dart](./Chapter_1/00-Introduction_to_ROHD.md#example-of-rohd-with-dart)
- [Setup & Installation](./Chapter_1/01-Setup_Installation.md)
  - [Setup on Github Codespaces](./Chapter_1/01-Setup_Installation.md#setup-on-github-codespaces-recommended)
  - [Local Development Setup](./Chapter_1/01-Setup_Installation.md#local-development-setup)
  - [Docker Container Setup](./Chapter_1/01-Setup_Installation.md#docker-container-setup)

## Chapter 2: Basic Gates

- Basic logic
  - Generate a two-input AND gate
  - First gate (simple & inside a main function)
  - Non-synthesizable signal deposition (put)
  - Explaining Logic and LogicValue
  - Adding widths to Logics
  - More operations (math, shift, unary, etc.)
  - Constants
  - Ranges and swizzling

## Chapter 3: Unit Testing

- Full-Adder Tutorial with TDD
- Simple unit test of existing logic
- Link to test package from Dart

## Chapter 4: Basic Generation

- Basic generation: Put adder in a loop (N-Bits Adder)
- Conditional generation and flow control
- Using functions to construct hardware
- Using classes to construct hardware
- Make a function on one bit full-adder and make a for loop that loop through this adder to make N-bit full adder.

## Chapter 5: Basics of modules

- Full Adder in Module
- Explanation of purpose of modules (introduce formal hierarchy)
- First module (one input, one output, simple logic)
- Converting to SystemVerilog
- Composing modules within other modules
- Port

## Chapter 6: Combinational Logic

- Combinational Logic: Simple Assignments, Full Adder but with Combinational Blocks, Add stuff together when something is equal
- Explanation of Conditionals
- Example of Combinational
- Conditional assignments
- If/Else, Case/CaseZ, etc.

## Chapter 7: Sequential Logic

- Shift Register
- Example of Sequential
- Simulator (Merged with tutorial 8)
- Explanation of role of Simulator
- Registering arbitrary events
- Starting and running the simulator
- Clock generator
- Run a sequential logic module in the simulator
- Non-synthesizable signal deposition (inject vs. put)
- WaveDumper, and view waves
- Interfaces (<https://en.wikipedia.org/wiki/Serial_Peripheral_Interface>)

## Chapter 8: Abstractions

- Pipelines: Normally Delayed exists in between a big circuit, abstractions split the logic across multiple cycles and let us decide what logic do you want it to occur in each of the cycle.
- Finite state machines

## Chapter 9: ROHD-COSIM External SystemVerilog Modules (Coming Soon!)

- More functionality
- Using and depending on other packages

## Chapter 10: ROHD-VF (Coming Soon!)

- Contributing to ROHD
- Building your own package
- ROHD-VF (<https://colorlesscube.com/uvm-guide-for-beginners/chapter-1-the-dut/>)
- ROHD Cosim

----------------
2023 February 13
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

Copyright (C) 2021-2023 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause

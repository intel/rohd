# Content Page

## Chapter 1: Getting Started

- [Introduction to ROHD](./chapter_1/00_introduction_to_rohd.md)
  - [What is ROHD?](./chapter_1/00_introduction_to_rohd.md)
  - [Challenges in Hardware Industry](./chapter_1/00_introduction_to_rohd.md#challenges-in-hardware-industry)
  - [Benefits of Dart for hardware development](./chapter_1/00_introduction_to_rohd.md#benefits-of-dart-for-hardware-development)
  - [Example of ROHD with Dart](./chapter_1/00_introduction_to_rohd.md#example-of-rohd-with-dart)
- [Setup & Installation](./chapter_1/01_setup_installation.md)
  - [Setup on Github Codespaces](./chapter_1/01_setup_installation.md#setup-on-github-codespaces-recommended)
  - [Local Development Setup](./chapter_1/01_setup_installation.md#local-development-setup)
  - [Docker Container Setup](./chapter_1/01_setup_installation.md#docker-container-setup)

## Chapter 2: Basic Gates

- [Basic logic](./chapter_2/00_basic_logic.md#basic-logic)
  - [Logic](./chapter_2/00_basic_logic.md#logic)
    - [Exercise 1](./chapter_2/00_basic_logic.md#exercise-1)
  - [Logic Value & Width](./chapter_2/00_basic_logic.md#logic-value--width)
  - [Logic Gate: Part 1](./chapter_2/00_basic_logic.md#logic-gate-part-1)
    - [Assignment, Logical, Mathematical, Comparison Operations](./chapter_2/00_basic_logic.md#assignment-logical-mathematical-comparison-operations)
      - [Assignment](./chapter_2/00_basic_logic.md#assignment)
      - [Logical, Mathematical, Comparison Operations](./chapter_2/00_basic_logic.md#logical-mathematical-comparison-operations)
  - [Logic Gate: Part 2](./chapter_2/00_basic_logic.md#logic-gate-part-2)
    - [Non-synthesizable signal deposition (put)](./chapter_2/00_basic_logic.md#non-synthesizable-signal-deposition-put)
    - [Exercise 2](./chapter_2/00_basic_logic.md#exercise-2)
  - [Logic Gate: Part 3](./chapter_2/00_basic_logic.md#logic-gate-part-3)
    - [Exercise 3](./chapter_2/00_basic_logic.md#exercise-3)
- [Constants](./chapter_2/00_basic_logic.md#constants)
  - [Exercise 4](./chapter_2/00_basic_logic.md#exercise-4)
- [Bus Ranges and Swizzling](./chapter_2/00_basic_logic.md#bus-ranges-and-swizzling)

## Chapter 3: Unit Testing

- [Introduction to Test Driven Development](./chapter_3/00_unit_test.md#introduction-to-test-driven-development)
- [What is a Full-Adder?](./chapter_3/00_unit_test.md#what-is-a-full-adder)
- [Create a Full-Adder with TDD](./chapter_3/00_unit_test.md#create-full-adder-with-tdd)
- [Exercise](./chapter_3/00_unit_test.md#exercise)

## Chapter 4: Basic Generation

- [What is n-bit adder?](./chapter_4/00_basic_generation.md#what-is-n-bit-adder)
- [Create a unit-test](./chapter_4/00_basic_generation.md#create-a-unit-test)
- [Create Dart function and class](./chapter_4/00_basic_generation.md#create-dart-function-and-class)
- [Exercise](./chapter_4/00_basic_generation.md#exercise)

## Chapter 5: Basics of modules

- [What is ROHD Module?](./chapter_5/00_basic_modules.md#what-is-rohd-module)
- [First module (one input, one output, simple logic)](./chapter_5/00_basic_modules.md#first-module-one-input-one-output-simple-logic)
- [Converting ROHD Module to System Verilog RTL](./chapter_5/00_basic_modules.md#converting-rohd-module-to-system-verilog-rtl)
- [Exercise 1](./chapter_5/00_basic_modules.md#exercise-1)
- [Composing modules within other modules (N-Bit Adder)](./chapter_5/00_basic_modules.md#composing-modules-withon-other-modules-n-bit-adder)
- [Exercise 2](./chapter_5/00_basic_modules.md#exercise-2)

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
- Interfaces <https://en.wikipedia.org/wiki/Serial_Peripheral_Interface>

## Chapter 8: Abstractions

- Pipelines: Normally Delayed exists in between a big circuit, abstractions split the logic across multiple cycles and let us decide what logic do you want it to occur in each of the cycle.
- Finite state machines

## Chapter 9: ROHD-COSIM External SystemVerilog Modules (Coming Soon!)

- More functionality
- Using and depending on other packages

## Chapter 10: ROHD-VF (Coming Soon!)

- Contributing to ROHD
- Building your own package
- ROHD-VF <https://colorlesscube.com/uvm-guide-for-beginners/chapter-1-the-dut/>
- ROHD Cosim

----------------
2023 February 13
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause

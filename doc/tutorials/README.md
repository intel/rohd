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

- [What is Combinational Logic?](./chapter_6/00_combinational_logic.md#what-is-combinational-logic)
- [What is Conditionals?](./chapter_6/00_combinational_logic.md#what-is-conditionals)
- [If, ElseIf, Else](./chapter_6/00_combinational_logic.md#if-elseif-else)
  - [Start by declaring a conditional Block](./chapter_6/00_combinational_logic.md#start-by-declaring-a-conditional-block)
  - [Add the condition inside the conditional block](./chapter_6/00_combinational_logic.md#add-the-condition-inside-the-conditional-block)
- [Case](./chapter_6/00_combinational_logic.md#case)
  - [Start by declaring a case](./chapter_6/00_combinational_logic.md#start-by-declaring-a-case)
  - [Add Expressions](./chapter_6/00_combinational_logic.md#add-expressions)
  - [Add Case Items](./chapter_6/00_combinational_logic.md#add-case-items)
  - [Add Default Items](./chapter_6/00_combinational_logic.md#add-default-items)
  - [Encapsulate case into a Combinational](./chapter_6/00_combinational_logic.md#encapsulate-case-into-a-combinational)
- [Exercises](./chapter_6/00_combinational_logic.md#exercises)

## Chapter 7: Sequential Logic

- [What is Sequential Logic?](./chapter_7/00_sequential_logic.md#what-is-sequential-logic)
- [Sequential Logic in ROHD](./chapter_7/00_sequential_logic.md#sequential-logic-in-rohd)
- [Shift Register](./chapter_7/00_sequential_logic.md#shift-register)
- [ROHD Simulator](./chapter_7/00_sequential_logic.md#rohd-simulator)
- [Unit Test in Sequential Logic](./chapter_7/00_sequential_logic.md#unit-test-in-sequential-logic)
- [Wave Dumper](./chapter_7/00_sequential_logic.md#wave-dumper)
- [Exercise](./chapter_7/00_sequential_logic.md#exercise)

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
2023 June 9
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause

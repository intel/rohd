# Rapid Open Hardware Development (ROHD)

The Rapid Open Hardware Development Framework (ROHD) is a generator framework for describing and verifying hardware using the Dart programming language. It allows for the construction and traversal of a connectivity graph between module objects using unrestricted software.

ROHD is a bold project with the goal of becoming the industry-standard choice for front-end hardware development, replacing System Verilog. It aims to address hardware problems in a similar way to Chisel, using Dart as its programming language of choice instead of Scala for several reasons.

1. Dart's popularity as a front-end framework, demonstrated by the success of Flutter, a framework for building IOS and Android apps, presents an opportunity for ROHD to leverage its success in the front-end generator RTL framework.

2. Dart offers asynchronous capabilities without the need for multithreading, making it easy to model and interact with hardware.

3. Dart was designed for front-end frameworks. It features both a just-in-time compiler in a virtual machine and an ahead-of-time compiler that can convert to native binaries on various platforms, providing multi-platform support.

4. Dart is a type-safe language that comes with type inference, linting, and other helpful plugins for IDEs such as Visual Studio Code to aid in the development process.

5. Dart is easy to learn, especially for those with experience in languages such as Java, C#, or JavaScript. 

## Challenges in Hardware Industry

The question of why it is necessary to replace legacy systems that have served well for so long is one that is often asked. In the following section, we will outline and enumerate the reasons why ROHD is considered a strong and promising standard.

1. **Challenges of SystemVerilog**: Despite being widely utilized in front-end hardware design and development, SystemVerilog (SV) does present certain limitations in hardware description. As a result, many designers have to complement SV with supplementary tools for hardware generation and interconnectivity.

2. **Inefficiency for Testbench Development**: Testbenches are often considered software, but the language in which they are written - SystemVerilog - does not always meet the demands of software development. Despite this, it is still commonly used because it facilitates interaction with hardware and related tools. To improve the efficiency of testbench development, it is suggested to use a modern programming language that offers advanced features. Furthermore, executing testbenches natively as software will provide a more comprehensive view of the test results, rather than relying on a black-box tool that only reveals limited information.

3. **Difficulties in Integrating and Reusing Code**:  Integrating and utilizing existing code can present significant difficulties, often taking several weeks to months of time and effort, just to integrate a same IP.

4. **Slow Development Iteration**: The development process in hardware is hindered by slow iteration time, causing a significant lag between code modification and the evaluation of its effectiveness. While smaller Intellectual Properties (IPs) may only take a few minutes or hours per iteration, larger System-on-Chips (SoCs) can take several days to complete the evaluation process.

5. **Insufficient Alternative Solutions**: While options such as Chisel and CoCoTB exist as alternatives in hardware development, they are not comprehensive solutions. Some prioritize design over verification, despite the significant amount of effort required for verification. Additionally, some solutions may have academic applications but lack practical feasibility for production use. To address these limitations, ROHD was designed to provide a ready-to-execute solution for hardware development.

6. **Lack of Open-Source Hardware Community**: The open-source hardware community is currently limited, with only a few available open-source generators or cores of varying quality. Access to open-source verification components is also limited, and there are no open-source or free tool options for running UVM testbenches. This presents challenges for hardware engineers who are unfamiliar with open-source development practices.

7. **Important of Collaboration in the Hardware Industry**: The software industry has long embraced the advantages of collaborating on open-source projects, including with competitors. In contrast, hardware engineers often struggle with inadequate tools and infrastructure, taking valuable time and energy away from their core competencies. By investing in open-source initiatives, these challenges can be alleviated and the efficiency of hardware development can be enhanced.

## Feature of ROHD

1. **Scalability**: The Dart programming language provides better scalability compared to system Verilog. It makes it easier to maintain and scale hardware designs as they become larger and more complex.

2. **Improved Productivity**: The Dart language is easier to use, learn and has better readability compared to system Verilog. This makes hardware development faster, easier and more efficient.

3. **Enhanced Verification**: The use of Dart as a programming language for hardware design allows for better and more efficient verification of hardware designs. This helps to reduce design and verification time and improve the overall quality of the hardware.

4. **Multi-platform Support**: Dart was designed from the ground up to be multi-platform, meaning it can be used to develop hardware for a variety of platforms, including both software and hardware (Chipyard, Firesim, Rocketchip, and NVDLA).

5. **Better Debugging**: Dart has better debugging tools compared to system Verilog, making it easier to identify and fix issues in hardware designs.

6. **Increased Reusability**: Dart allows for the creation of reusable and modular hardware designs, making it easier to reuse components across multiple projects and speeding up the development process.

7. **Open-source Community**: The Dart language has a strong open-source community, providing a wealth of resources and support to hardware developers. This helps to drive innovation and development in the field.

----------------
2023 February 13
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

 
Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause
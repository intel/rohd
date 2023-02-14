# Rapid Open Hardware Development (ROHD)

The Rapid Open Hardware Development Framework (ROHD) is a generator framework for describing and verifying hardware using the Dart programming language. It allows for the construction and traversal of a connectivity graph between module objects using unrestricted software.

ROHD is a bold project with the goal of becoming the industry-standard choice for front-end hardware development, replacing System Verilog. It aims to address hardware problems in a similar way to Chisel, using Dart as its programming language of choice instead of Scala for several reasons.

1. Dart's popularity as a front-end framework, demonstrated by the success of Flutter, a framework for building IOS and Android apps, presents an opportunity for ROHD to leverage its success in the front-end generator RTL framework.

2. Dart offers asynchronous capabilities without the need for multithreading, making it easy to model and interact with hardware.

3. Dart was designed for front-end frameworks. It features both a just-in-time compiler in a virtual machine and an ahead-of-time compiler that can convert to native binaries on various platforms, providing multi-platform support.

4. Dart is a type-safe language that comes with type inference, linting, and other helpful plugins for IDEs such as Visual Studio Code to aid in the development process.

5. Dart is easy to learn, especially for those with experience in languages such as Java, C#, or JavaScript. 

## Challenges in Hardware Industry

Many people are curious as to why it is necessary to overhaul legacy systems that have proven effective for so long. Below, are some of the reasons why ROHD can be viewed as a powerful potential standard replacement.

1. **Limitations of SystemVerilog**: SystemVerilog (SV) is widely used in front-end hardware design and development, but it has limitations in hardware description. Many designers resort to using additional tools for hardware generation and connectivity due to these limitations.

2. **Inefficiency for Testbench Development**: Testbenches are software, and writing software in SystemVerilog is not ideal due to its inefficiency for software development. SystemVerilog's popularity can be attributed to the fact that it is convenient for verification engineers as it allows them to interact with hardware and related tools using the same language and tool stack.

3. **Difficulties in Integrating and Reusing Code**: Integrating and reusing SystemVerilog code can be extremely challenging and time-consuming.  Sometimes even just re-integrating a newer version of an existing component can take weeks.

4. **Slow Development Iteration**: Hardware development today is plagued by slow iteration time (usually build + simulation time), meaning that every time code is changed it takes a long time to determine if the change is effective. Smaller IPs may take only a few minutes or hours per iteration, but large SoCs can take days.

5. **Insufficient Alternative Solutions**: While there are alternative solutions such as Chisel and cocotb, they do not address all of the problems in hardware development. Some treat verification as a secondary consideration, despite the fact that verification often requires twice as much effort as design. Some solutions are academic in nature, but not suitable for production use. ROHD was developed as a solution that is ready for execution and addresses a wide range of front-end development needs.

6. **Lack of Open-Source Hardware Community**: The open-source hardware community is lacking. There are a few open-source generators or cores available, but their quality can be inconsistent. Finding open-source verification components is also a challenge, and there are no open-source or free tool stacks that can run UVM testbenches. This leaves many hardware engineers unfamiliar with open-source development.

7. **Need for Collaboration in the Hardware Industry**: The software industry has long recognized the benefits of collaborating on open-source projects, even with competitors. Hardware engineers, on the other hand, often spend too much time on struggling with poor tools and infrastructure. Instead of focusing on their competitive advantages, they are bogged down by these issues. Investing in open-source projects can help alleviate these challenges and improve the overall efficiency of hardware development.

## Benefits of Dart for Hardware Development

1. **Scalability**: The Dart programming language provides better scalability compared to SystemVerilog. It makes it easier to maintain and scale hardware designs as they become larger and more complex.

2. **Improved Productivity**: The Dart language is easier to use and learn and has better readability compared to SystemVerilog. This makes hardware development faster, easier, and more efficient.

3. **Enhanced Verification**: The use of Dart as a programming language for hardware design allows for better and more efficient verification of hardware designs. This helps to reduce design and verification time and improve the overall quality of the hardware.

4. **Multi-platform Support**: Dart was designed from the ground up to be multi-platform, meaning it can be used to develop hardware for a variety of platforms, including both software and hardware.

5. **Better Debugging**: Dart has better debugging and profiling tools compared to SystemVerilog, making it easier to identify and fix issues in hardware designs.

6. **Increased Reusability**: Dart with ROHD allows for the creation of reusable and modular hardware designs, making it easier to reuse components across multiple projects and speeding up the development process.

7. **Open-source Community**: The Dart language has a strong open-source community, providing a wealth of resources and support to hardware developers. This helps to drive innovation and development in the field.

----------------
2023 February 13
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

 
Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause
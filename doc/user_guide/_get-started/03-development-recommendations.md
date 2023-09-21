---
title: "Development Recommendations"
permalink: /get-started/development-recommendations/
excerpt: "Development Recommendations"
last_modified_at: 2023-6-19
toc: true
---

- The [ROHD Verification Framework](https://github.com/intel/rohd-vf) is a UVM-like framework for building testbenches for hardware modelled in ROHD.
- The [ROHD Cosimulation](https://github.com/intel/rohd-cosim) package allows you to cosimulate the ROHD simulator with a variety of SystemVerilog simulators.
- The [ROHD Hardware Component Library](https://github.com/intel/rohd-vf) provides a set of reusable and configurable components for design and verification.
- Visual Studio Code (vscode) is a great, free IDE with excellent support for Dart.  It works well on all platforms, including native Windows or Windows Subsystem for Linux (WSL) which allows you to run a native Linux kernel (e.g. Ubuntu) within Windows.  You can also use vscode to develop on a remote machine with the Remote SSH extension.
  - vscode: <https://code.visualstudio.com/>
  - WSL: <https://docs.microsoft.com/en-us/windows/wsl/install-win10>
  - Remote SSH: <https://code.visualstudio.com/blogs/2019/07/25/remote-ssh>
  - Dart extension for vscode: <https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code>

Head over to the [user guide]({{ site.baseurl }}{% link _docs/A01-sample-example.md %}) to learn more about how to use ROHD.

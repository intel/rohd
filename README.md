<p align="center">
  <img alt="ROHD" src="https://intel.github.io/rohd-website/assets/images/rohd_logo_w_white_background.svg">
</p>

# Rapid Open Hardware Development (ROHD) Framework

[![Tests](https://github.com/intel/rohd/actions/workflows/general.yml/badge.svg?event=push)](https://github.com/intel/rohd/actions/workflows/general.yml)
[![API Docs](https://img.shields.io/badge/API%20Docs-generated-success)](https://intel.github.io/rohd/rohd/rohd-library.html)
[![Chat](https://img.shields.io/discord/1001179329411166267?label=Chat)](https://discord.gg/jubxF84yGw)
[![License](https://img.shields.io/badge/License-BSD--3-blue)](https://github.com/intel/rohd/blob/main/LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](https://github.com/intel/rohd/blob/main/CODE_OF_CONDUCT.md)

ROHD (pronounced like "road") is a framework for describing and verifying hardware in the Dart programming language.

## Documentation

For documentation, guides, and more, [**visit the ROHD Website!**](https://intel.github.io/rohd-website/)

- [Install now](https://intel.github.io/rohd-website/get-started/overview/)
- [Try it in-browser](https://dartpad.dev/?id=375e800a9d0bd402c9bfa5ebe2210c40)
- [User Guide](https://intel.github.io/rohd-website/docs/sample-example/)
- [Tutorials](https://github.com/intel/rohd/tree/main/doc/tutorials)
- [YouTube Channel](https://www.youtube.com/@ROHD-DEV)
- [API Docs](https://intel.github.io/rohd/rohd/rohd-library.html)
- [Blog](https://intel.github.io/rohd-website/blog/)
- [Contributing](https://github.com/intel/rohd/blob/main/CONTRIBUTING.md)

You can also open this repository in a GitHub Codespace to run the example in your browser with a full IDE.  This is also an easy way to get started with contributions!

  [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=409325108)

### Get involved

- [Join the Discord chat](https://discord.gg/jubxF84yGw)
- [Attend the ROHD Forum meetings](https://intel.github.io/rohd-website/forum/rohd-forum/)
- [GitHub Discussions](https://github.com/intel/rohd/discussions)

## About ROHD

- Full power of the modern **Dart language** for hardware design and verification
- Makes **validation collateral** simpler to develop and debug.  The [ROHD Verification Framework](https://github.com/intel/rohd-vf) helps build well-structured testbenches.
- Develop **layers of abstraction** within a hardware design, making it more flexible and powerful
- Easy **IP integration** and **interfaces**; using an IP is as easy as an import.  Reduces tedious, redundant, and error prone aspects of integration
- **Simple and fast build**, free of complex build systems and EDA vendor tools
- Can use the excellent pub.dev **package manager** and all the packages it has to offer
- Built-in event-based **fast simulator** with **4-value** (0, 1, X, and Z) support and a **waveform dumper** to .vcd file format
- Conversion of modules to equivalent, human-readable, structurally similar **SystemVerilog** for integration or downstream tool consumption
- **Run-time dynamic** module port definitions (numbers, names, widths, etc.) and internal module logic, including recursive module contents
- Leverage the [ROHD Hardware Component Library (ROHD-HCL)](https://github.com/intel/rohd-hcl) with reusable and configurable design and verification components.
- Simple, free, **open source tool stack** without any headaches from library dependencies, file ordering, elaboration/analysis options, +defines, etc.
- Excellent, simple, fast **unit-testing** framework
- **Less verbose** than alternatives (fewer lines of code)
- Enables **higher quality** development
- Replaces hacky perl/python scripting for automation with powerful **native control of design generation**
- Fewer bugs and lines of code means **shorter development schedule**
- Support for **cosimulation with verilog modules** (via [ROHD Cosim](https://github.com/intel/rohd-cosim)) and **instantiation of verilog modules** in generated SystemVerilog code
- Use **modern IDEs** like Visual Studio Code, with excellent static analysis, fast autocomplete, built-in debugger, linting, git integration, extensions, and much more
- Simulate with **various abstraction levels of models** from architectural, to functional, to cycle-accurate, to RTL levels in the same language and environment.

ROHD is *not* a new language, it is *not* a hardware description language (HDL), and it is *not* a version of High-Level Synthesis (HLS).  ROHD can be classified as a generator framework.

You can think of this project as an attempt to *replace* SystemVerilog and related build systems as the front-end methodology of choice in the industry.

One of ROHD's goals is to help grow an open-source community around reusable hardware designs and verification components.

## Contributing

ROHD is under active development.  If you're interested in contributing, have feedback or a question, or found a bug, please see [CONTRIBUTING.md](https://github.com/intel/rohd/blob/main/CONTRIBUTING.md).

----------------

Copyright (C) 2021-2025 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause

# Contributing to ROHD

Thank you for considering contributing to ROHD! Contributions from the community are vital to making this a successful project.

Anyone interested in participating in ROHD is more than welcome to help!

## Code of Conduct

ROHD adopts the [Contributor Covenant](https://www.contributor-covenant.org/) v2.1 for the code of conduct. It can be accessed [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Help

### Chat on Discord

[Discord](https://discord.com/) is a free online instant messaging app which you can use directly in your web browser or install to your device. Feel free to join to look around at the conversations and have a real-time discussion with the ROHD community. This a great place to ask questions, get help, engage with the rest of the community, and discuss new ideas.

Join the Discord server here: <https://discord.com/invite/jubxF84yGw>

### GitHub Discussions

GitHub Discussions is a place where you can find announcements, ask questions, share ideas, show new things you're working on, or just discuss in general with the community! If you have a question or need some help, this is a great place to go.

You can access the discussions area here: <https://github.com/intel/rohd/discussions>

### GitHub Issues

If something doesn't seem right, you're stuck, there's a critical feature/enhancement missing, you find a bug, etc. then filing an issue on the GitHub repository is a great option. Please try to provide as much detail as possible. Complete, stand-alone reproduction instructions are extremely helpful for bugs!

You can file an issue here: <https://github.com/intel/rohd/issues/new/choose>

### Stack Overflow

[Stack Overflow](https://stackoverflow.com/) is a great tool to ask questions and get answers from the community. Use the `rohd` tag when asking your question so that others in the community who subscribe to that tag can find and answer your question more quickly!

### Meetings in the ROHD Forum

The [ROHD Forum](https://intel.github.io/rohd-website/forum/rohd-forum/) is a periodic virtual meeting for developers and users of ROHD that anyone can join. Feel free to join the call!

## Getting Started

### Requirements

ROHD uses a [pub workspace](https://dart.dev/tools/pub/workspaces) for its
active packages. [Dart](https://dart.dev/get-dart) is sufficient to develop,
analyze, and test the core ROHD package. Install
[Flutter](https://docs.flutter.dev/get-started/install), which includes a
compatible Dart SDK, to develop the DevTools application or validate the full
mixed Dart/Flutter workspace.

To run the complete ROHD test suite for development, you need to install [Icarus Verilog](https://steveicarus.github.io/iverilog/). It is used to compare SystemVerilog functionality with the ROHD simulator functionality. Installation instructions are available here: <https://iverilog.fandom.com/wiki/Installation_Guide>

### Setup Recommendations

#### On your own system

[Visual Studio Code (VSCode)](https://code.visualstudio.com/) is a great IDE for development. You can find installation instructions for VSCode here: <https://code.visualstudio.com/download>

The Dart extension extends VSCode with support for the Dart programming language and provides tools for effectively editing, refactoring and running. Check out the detailed information: <https://dartcode.org/>

If you're developing on a remote host, VSCode has a Remote SSH extension that can help: <https://code.visualstudio.com/docs/remote/ssh>

If you're on Microsoft Windows, you may want to consider developing with Ubuntu WSL for a Linux environment: <https://learn.microsoft.com/windows/wsl/install>

#### In GitHub Codespaces

[GitHub Codespaces](https://github.com/features/codespaces) are a great feature provided by GitHub allowing you to get into a development environment based on a pre-configured container very quickly! You can use them for a limited number of hours per month for free. ROHD has set up GitHub Codespaces so that you can immediately start running examples and developing.

The below button will allow you to create a GitHub Codespace with ROHD already cloned and ready to roll:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=409325108)

### Core ROHD Setup and Validation

The root [`pubspec.yaml`](pubspec.yaml) `workspace:` list defines the active
packages. The legacy
[`doc/tutorials/chapter_9/rohd_vf_example`](doc/tutorials/chapter_9/rohd_vf_example)
is intentionally outside the workspace because it demonstrates an older
published ROHD release.

For core ROHD development, clone the repository and use Dart from the
repository root:

```shell
git clone https://github.com/intel/rohd.git
cd rohd

# Resolve the core package and workspace dependencies.
dart pub get

# Open Folder: open only the root ROHD package in VSCode.
code .

# Analyze and test the core package.
dart analyze
dart test
```

As a local convenience, `tool/gh_actions/install_dependencies.sh` performs the
same dependency-resolution step. It uses Flutter for the full workspace when
Flutter is installed and otherwise uses Dart for the core package.

In VSCode, this is equivalent to **File > Open Folder...** and selecting the
repository root. Use this mode when working only on the core ROHD package.

### Full Workspace Setup, VSCode, and Validation

For DevTools development or repository-wide validation, use Flutter to resolve
the mixed Dart/Flutter workspace. The checked-in
[`rohd-multipackage.code-workspace`](rohd-multipackage.code-workspace) is
generated from the root `workspace:` list, so it can be opened immediately
after cloning:

```shell
# Open Workspace from File: open every active member in its own package context.
code rohd-multipackage.code-workspace

# Resolve every workspace member from a terminal at the repository root.
flutter pub get
```

In VSCode, this is equivalent to **File > Open Workspace from File...** and
selecting `rohd-multipackage.code-workspace`. Do not use **Open Folder** for
all-package work: the generated multi-root workspace gives each active package
its own Dart or Flutter package context.

After opening the generated workspace, select the Flutter-bundled Dart SDK if
the Dart extension does not select it automatically. The generated workspace
includes every active member, so Dart and Flutter analysis can resolve package
boundaries correctly.

Run repository-wide validation from the repository root:

```shell
# Analyze every active workspace member.
dart run tool/workspace.dart analyze

# Run native tests, using flutter test for Flutter packages.
dart run tool/workspace.dart test

# Run Node.js tests for each non-Flutter workspace member.
dart run tool/workspace.dart test-node
```

The Node.js pass can take substantially longer than native tests because Dart
compiles browser test bundles. Run an individual package or test file directly
while iterating, then use the workspace commands before submitting a change.

When adding or removing an active package, update the root `workspace:` list,
regenerate `rohd-multipackage.code-workspace` with
`dart run tool/workspace.dart vscode`, and commit the generated workspace file
alongside the `pubspec.yaml` change. Then run `flutter pub get`.

## How to Contribute

### Reporting Vulnerabilities

Please report any vulnerabilities according to the information provided in the [SECURITY.md](SECURITY.md) file.

### Reporting Bugs

Please report any bugs you find as a GitHub issue. Please try to provide as much detail as possible. Complete, stand-alone reproduction instructions are extremely helpful for bugs!

Some helpful information you can include:

* Output of `dart --version`
* Your dependencies from `pubspec.yaml`
* The version of ROHD you're using
* Command you ran and output
* Reproduction code and steps

### Suggesting Enhancements

If you have an idea for a feature or enhancement that would make ROHD better, feel free to submit a GitHub issue! Discussion on the ticket about pros & cons, strategy, etc. is encouraged.

### Discussing Issues

If you have an opinion or helpful information on any open issue, feel free to comment! Even if you don't have the time to implement a change, providing valuable input is great too!

### Fix or implement an Issue

Take a look around the issues on the repo and see if there's any you'd like to take ownership of. For your first contributions, look for issues tagged with `good first issue`, which are intended to be easier to get started with. Feel free to ask for help or guidance!

### Pull Requests

If you have a change that you have implemented and would like to contribute, you can open a pull request. Please try to make sure you have implemented tests covering the changes, if applicable. Smaller, simpler pull requests are easier to review.

Be sure to run the applicable workspace validation commands described above
before asking for your code to be merged. You may also locally generate API
documentation (`dart doc`) to make sure it looks right and doesn't have any
errors. You should use the dart formatter on all code (`dart format .`), and
may prefer to have it automatically format on every file save. If you are using
VSCode with the Dart extension, then consider using the recommended settings:
<https://dartcode.org/docs/recommended-settings/>

**Tests must pass, documentation must generate, and the formatter must be run on every pull request or the automated GitHub Actions flow will fail.**

Maintainers of the project and other community members will provide feedback and help iterate as necessary until the contribution is ready to be merged.

Please include the SPDX tag near the top of any new files you create:

```dart
// SPDX-License-Identifier: BSD-3-Clause
```

Here is an example of a recommended file header template:

```dart
// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// example.dart
// A very basic example of a counter module.
//
// 2021 September 17
// Author: Max Korbel <max.korbel@intel.com>
```

You may find that reading the [Architecture](doc/architecture.md) document will be helpful to becoming familiar with the design of the ROHD framework.

### Creating a New Package

Not every new contribution has to go directly into the ROHD framework! If you have an idea for a reusable piece of hardware, tooling, verification collateral, or anything else that helps the ROHD ecosystem but is somewhat standalone, you can make your own package that depends on ROHD. Building an ecosystem of reusable components is important to the success of ROHD. Reach out if you want some help or guidance deciding if or how you should create a new package.

## Style

ROHD follows the official Dart recommended style guides and lints. The analyzer will help ensure that your code is written consistently with the rest of ROHD.

Here are some links to help guide you on style as recommended by Dart:

* Effective Dart: <https://dart.dev/guides/language/effective-dart>
* Style: <https://dart.dev/guides/language/effective-dart/style>
* Documentation: <https://dart.dev/guides/language/effective-dart/documentation>
* Usage: <https://dart.dev/guides/language/effective-dart/usage>
* Design: <https://dart.dev/guides/language/effective-dart/design>

We recommend following these same guidelines for any of your own packages you may create for the ecosystem, as well.

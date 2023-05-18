---
title: "Setup & Install"
permalink: /get-started/setup/
excerpt: "Instructions for installing the theme for new and existing Jekyll based sites."
last_modified_at: 2023-01-03
toc: true
---

## Getting started

Follow the instruction at [https://dart.dev/get-dart](https://dart.dev/get-dart) to install `dart` in your environment.

Once you have Dart installed, if you don't already have a project, you can create one using `dart create`: [https://dart.dev/tools/dart-tool](https://dart.dev/tools/dart-tool)

Then add ROHD as a dependency to your pubspec.yaml file.  ROHD is [registered](https://pub.dev/packages/rohd) on pub.dev.  The easiest way to add ROHD as a dependency is following the instructions here [https://pub.dev/packages/rohd/install](https://pub.dev/packages/rohd/install).

Now you can import it in your project using:

```dart
import 'package:rohd/rohd.dart';
```

There are complete API docs available at [https://pub.dev/documentation/rohd/latest/](https://pub.dev/documentation/rohd/latest/).

If you need some help, you can join the [Discord server](https://discord.com/invite/jubxF84yGw) or visit our [Discussions](https://github.com/intel/rohd/discussions) page.  These are friendly places where you can ask questions, share ideas, or just discuss openly!  You could also head to [StackOverflow.com](https://stackoverflow.com/) (use the tag `rohd`) to ask questions or look for answers.

You also may be interested to join the [ROHD Forum](https://github.com/intel/rohd/wiki/ROHD-Forum) periodic meetings with other users and developers in the ROHD community.  The meetings are open to anyone interested!

Be sure to note the minimum Dart version required for ROHD specified in pubspec.yaml (at least 2.18.0).  If you're using the version of Dart that came with Flutter, it might be older than that.

## Package Managers for Hardware

In the Dart ecosystem, you can use a package manager to define all package dependencies.  A package manager allows you to define constrainted subsets of versions of all your *direct* dependencies, and then the tool will solve for a coherent set of all (direct and indirect) dependencies required to build your project.  There's no need to manually figure out tool versions, build flags and options, environment setup, etc. because it is all guaranteed to work.  Integration of other packages (whether a tool or a hardware IP) become as simple as an `import` statment.  Compare that to SystemVerilog IP integration!

Read more about package managers here: [https://en.wikipedia.org/wiki/Package_manager](https://en.wikipedia.org/wiki/Package_manager)  

Take a look at Dart's package manager, pub.dev, here: [https://pub.dev](https://pub.dev)

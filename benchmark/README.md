Benchmarking in ROHD
====================

This folder contains some benchmarking related code for estimating relative performance of certain ROHD features.  It can be used to help judge the relative performance impact with and without a change in ROHD.  Benchmarks can be microbenchmarks for a specific feature, larger benchmarks for estimating performance on more realistic designs, or comparison benchmarks for similar applications relative to other frameworks and simulators.

To run all benchmarks, execute the below command:

```shell
dart run benchmark/benchmark.dart
```

You can run this command (or specific benchmarks) before and after a change to get a feel if any performance covered by these benchmarks has been impacted.

----------------
2022 September 28
Author: Max Korbel <<max.korbel@intel.com>>

Copyright (C) 2022 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause

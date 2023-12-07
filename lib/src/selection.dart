// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selection.dart
// Definition for selecting a Logic from List<Logic> by a given index.

//
// 2023 November 14
// Author: Rahul Gautham Putcha <rahul.gautham.putcha@intel.com>

import 'package:rohd/rohd.dart';

/// Allows a lists of [Logic]s to have its elemets picked
/// by a [Logic] index value.
extension IndexedLogic on List<Logic> {
  /// Performs a [index] based selection on an [List] of [Logic].
  ///
  /// Given a [List] of [Logic] say `logicList` on which we apply [selectIndex]
  /// and an element [index] as argument , we can select any valid element
  /// of type [Logic] within the `logicList` using the [index] of [Logic] type.
  ///
  /// Alternatively we can approach this with `index.selectFrom(logicList)`
  ///
  /// Example:
  /// ```
  /// // ordering matches closer to array indexing with `0` index-based.
  /// List<Logic> logicList = [/* Add your Logic elements here */];
  /// selected <= index.selectIndex(logicList);
  /// ```
  ///
  Logic selectIndex(Logic index) => index.selectFrom(this);
}

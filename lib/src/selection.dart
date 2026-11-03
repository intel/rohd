// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selection.dart
// Definition for selecting a Logic from List<Logic> by a given index.
//
// 2023 November 14
// Author: Rahul Gautham Putcha <rahul.gautham.putcha@intel.com>

import 'package:rohd/rohd.dart';

/// Allows a list of [LogicType]s to have an element selected by a [Logic]
/// index.
extension IndexedLogic<LogicType extends Logic> on List<LogicType> {
  /// Performs an [index]-based selection on this list.
  ///
  /// Given a [List] of [Logic] say `logicList` on which we apply [selectIndex]
  /// and an element [index] as argument , we can select any valid element
  /// of type [Logic] within the `logicList` using the [index] of [Logic] type.
  ///
  /// Alternatively we can approach this with `index.selectFrom(logicList)`
  ///
  /// Example:
  /// ```dart
  /// // ordering matches closer to array indexing with `0` index-based.
  /// List<Logic> logicList = [/* Add your Logic elements here */];
  /// selected <= logicList.selectIndex(index);
  /// ```
  ///
  LogicType selectIndex(
    Logic index, {
    dynamic defaultValue,
    LogicType Function({String? name})? outputGenerator,
    String name = 'selectFrom',
  }) =>
      index.selectFrom(
        this,
        defaultValue: defaultValue,
        outputGenerator: outputGenerator,
        name: name,
      );
}

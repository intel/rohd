// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selection.dart
// Definition for select

//
// 2023 November 14
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

// ignore: public_member_api_docs
extension IndexedLogic on List<Logic> {
  // example
  // List<Logic> a; // length of list is 5, each element width is 9 bits
  // Logic b; // width is 3 bits
  // Logic c; // width is 9 bits
  /// write doc
  Logic selectIndex(Logic a) => a.selectFrom(this);
}

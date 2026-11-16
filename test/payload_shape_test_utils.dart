// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// payload_shape_test_utils.dart
// Downstream helper with the name used by older ROHD-HCL releases.
//
// 2026 November
// Author: ROHD Contributors

import 'package:rohd/rohd.dart';

bool sameDeclaredPayloadShape(Logic first, Logic second) =>
    identical(first, second);

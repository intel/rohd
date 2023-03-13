// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// timestamper.dart
// Utility for creating uniform timestamps.
//
// 2023 February 18
// Author: Chykon

/// Utility for creating timestamps.
abstract class Timestamper {
  /// Creates a timestamp in `YYYY-MM-DD hh:mm:ss.sss [+/-]hh:mm` format.
  static String stamp() {
    final now = DateTime.now();

    return '${now.toString().substring(0, 23)} ${_getUtcOffset(now)}';
  }

  /// Converts the timezone offset to `[+/-]hh:mm` format.
  static String _getUtcOffset(DateTime time) {
    final utcOffset =
        time.timeZoneOffset.abs().toString().split(':').sublist(0, 2);

    utcOffset.first = utcOffset.first.padLeft(2, '0');

    if (time.timeZoneOffset.isNegative) {
      utcOffset.first = '-${utcOffset.first}';
    } else {
      utcOffset.first = '+${utcOffset.first}';
    }

    return utcOffset.join(':');
  }
}

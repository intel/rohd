// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// occurrence_trie.dart
// Compact storage for values keyed by hierarchy occurrence addresses.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/occurrence_address.dart';

/// A prefix-sharing map from [OccurrenceAddress] values to values of type [T].
///
/// Common address prefixes are stored once, making this more compact than a
/// conventional map when many values belong to the same hierarchy subtree.
class OccurrenceTrie<T extends Object> {
  final _OccurrenceTrieNode<T> _root = _OccurrenceTrieNode<T>();

  /// Whether this trie contains no values.
  bool get isEmpty => _root.isEmpty;

  /// The value stored at [address], if any.
  T? operator [](OccurrenceAddress address) {
    var node = _root;
    for (final index in _validatedPath(address)) {
      final child = node.children[index];
      if (child == null) {
        return null;
      }
      node = child;
    }
    return node.value;
  }

  /// Associates [value] with [address].
  ///
  /// Returns the value previously stored at [address], if any.
  T? set(OccurrenceAddress address, T value) {
    var node = _root;
    for (final index in _validatedPath(address)) {
      node = node.children.putIfAbsent(index, _OccurrenceTrieNode<T>.new);
    }
    final previous = node.value;
    node.value = value;
    return previous;
  }

  /// Removes and returns the value stored at [address], if any.
  T? remove(OccurrenceAddress address) {
    final path = _validatedPath(address);
    final nodes = <_OccurrenceTrieNode<T>>[_root];
    var node = _root;
    for (final index in path) {
      final child = node.children[index];
      if (child == null) {
        return null;
      }
      nodes.add(child);
      node = child;
    }

    final previous = node.value;
    if (previous == null) {
      return null;
    }
    node.value = null;
    for (var index = path.length - 1; index >= 0; index--) {
      final child = nodes[index + 1];
      if (!child.isEmpty) {
        break;
      }
      nodes[index].children.remove(path[index]);
    }
    return previous;
  }

  /// Removes every value from this trie.
  void clear() {
    _root
      ..value = null
      ..children.clear();
  }

  static List<int> _validatedPath(OccurrenceAddress address) {
    if (address.path.isEmpty) {
      throw ArgumentError.value(
        address,
        'address',
        'A signal occurrence address must not be empty.',
      );
    }
    if (address.path.any((index) => index < 0)) {
      throw ArgumentError.value(
        address,
        'address',
        'A signal occurrence address must contain non-negative indices.',
      );
    }
    return address.path;
  }
}

class _OccurrenceTrieNode<T extends Object> {
  final Map<int, _OccurrenceTrieNode<T>> children = {};
  T? value;

  bool get isEmpty => value == null && children.isEmpty;
}

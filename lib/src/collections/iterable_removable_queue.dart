/// A queue that can be easily iterated through and remove items during
/// iteration.
class IterableRemovableQueue<T> {
  _IterableRemovableElement<T>? _first;
  _IterableRemovableElement<T>? _last;

  void add(T item) {
    final newElement = _IterableRemovableElement<T>(item);
    if (_first == null) {
      _first = newElement;
      _last = _first;
    } else {
      _last!.next = newElement;
      _last = newElement;
    }
  }

  bool get isEmpty => _first == null;

  void clear() {
    _first = null;
    _last = null;
  }

  /// Appends [other] to this without copying any elements and [clear]s [other].
  void takeAll(IterableRemovableQueue<T> other) {
    if (other.isEmpty) {
      return;
    }

    if (isEmpty) {
      _first = other._first;
      _last = other._last;
    } else {
      _last!.next = other._first;
      _last = other._last;
    }

    other.clear();
  }

  void forEach(void Function(T item) action,
      {bool Function(T item)? removeWhere}) {
    if (isEmpty) {
      return;
    }

    var element = _first;
    _IterableRemovableElement<T>? previous;
    while (element != null) {
      if (removeWhere != null && removeWhere(element.item)) {
        previous?.next = element.next;

        if (element == _first) {
          _first = element.next;
        } else if (element == _last) {
          _last = previous;
        }
      } else {
        action(element.item);

        previous = element;
      }

      element = element.next;
    }
  }
}

class _IterableRemovableElement<T> {
  final T item;

  _IterableRemovableElement<T>? next;

  _IterableRemovableElement(this.item);
}

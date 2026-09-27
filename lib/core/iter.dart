/// Своё имя, чтобы не зависеть от версии SDK и не конфликтовать с package:collection.
extension IterX<T> on Iterable<T> {
  T? get firstOrNone {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

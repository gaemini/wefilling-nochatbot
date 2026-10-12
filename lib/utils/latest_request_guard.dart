/// Prevents a slower, older asynchronous request from replacing the result of
/// a newer request.
///
/// Calling [begin] invalidates every token issued before it. Clearing a search
/// should call [invalidate] so an in-flight response cannot repopulate the UI.
class LatestRequestGuard {
  int _generation = 0;

  int begin() => ++_generation;

  void invalidate() {
    _generation++;
  }

  bool isCurrent(int token) => token == _generation;
}

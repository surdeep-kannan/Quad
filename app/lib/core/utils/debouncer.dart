import 'dart:async';

/// Runs the latest callback once calls stop for [delay].
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}

/// Lets a call through at most once per [interval].
class Throttler {
  Throttler(this.interval);

  final Duration interval;
  DateTime? _last;

  bool get ready => _last == null || DateTime.now().difference(_last!) >= interval;

  void call(void Function() action) {
    if (!ready) return;
    _last = DateTime.now();
    action();
  }
}

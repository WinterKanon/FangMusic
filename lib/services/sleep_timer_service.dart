import 'dart:async';

import 'package:flutter/foundation.dart';

/// 睡眠定时结束方式（v1.2）
enum SleepTimerMode {
  /// 到时间立即暂停
  pauseNow('到时间立即暂停'),

  /// 到时间后播完当前歌曲再暂停
  finishCurrent('播完当前歌曲再暂停');

  const SleepTimerMode(this.label);
  final String label;
}

/// 睡眠定时服务（v1.2）
///
/// - [pauseNow]：到点直接暂停；
/// - [finishCurrent]：到点标记 pending，当前歌播完由播放服务暂停、不切下一首；
/// - 到点后用户手动切歌/暂停 → 取消 pending，不再自动暂停；
/// - 到点时已暂停 → 结束定时，不自动播放。
class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService instance = SleepTimerService._();
  SleepTimerService._();

  DateTime? _deadline;
  SleepTimerMode _mode = SleepTimerMode.finishCurrent;
  Timer? _timer;
  Timer? _ticker;
  bool _pendingPause = false;

  /// 由播放服务注入：请求立即暂停 / 查询是否正在播放
  Future<void> Function()? pausePlayer;
  bool Function()? isPlaying;

  bool get active => _deadline != null;
  DateTime? get deadline => _deadline;
  SleepTimerMode get mode => _mode;
  bool get pendingPause => _pendingPause;

  Duration get remaining {
    final d = _deadline;
    if (d == null) return Duration.zero;
    final left = d.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  String get remainingLabel {
    final r = remaining;
    final m = r.inMinutes;
    final s = r.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void start(Duration duration, SleepTimerMode mode) {
    cancel();
    _mode = mode;
    _deadline = DateTime.now().add(duration);
    _pendingPause = false;
    _timer = Timer(duration, _onDeadline);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    notifyListeners();
  }

  void _onDeadline() {
    _timer = null;
    _ticker?.cancel();
    _ticker = null;
    if (_mode == SleepTimerMode.pauseNow) {
      final pause = pausePlayer;
      _deadline = null;
      notifyListeners();
      if (pause != null) unawaited(pause());
      return;
    }
    //播完当前歌再停：到点后等当前歌自然结束；若当前已暂停则不自动播放
    if (!(isPlaying?.call() ?? false)) {
      _clear();
      return;
    }
    _pendingPause = true;
    notifyListeners();
  }

  /// 当前歌自然播完时由播放服务查询；返回 true 表示本次应暂停不再连播
  bool consumePendingPause() {
    if (!_pendingPause) return false;
    _pendingPause = false;
    _deadline = null;
    _timer?.cancel();
    _ticker?.cancel();
    _timer = null;
    _ticker = null;
    notifyListeners();
    return true;
  }

  /// 用户手动切歌/暂停：取消到点后的待暂停（不自动暂停）
  void cancelPendingByManualAction() {
    if (!_pendingPause) return;
    _pendingPause = false;
    _clear();
  }

  void cancel() {
    _clear();
  }

  void _clear() {
    _deadline = null;
    _pendingPause = false;
    _timer?.cancel();
    _ticker?.cancel();
    _timer = null;
    _ticker = null;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';

import '../models/song_play_stat.dart';
import 'storage_service.dart';

/// 播放次数统计服务（v1.2）
///
/// 以音频路径为键，独立持久化到 `play_stats_database.json`；
/// 计数由播放服务在"持续播放 ≥5 秒"后调用 [recordStart]。
class PlaybackStatsService extends ChangeNotifier {
  static final PlaybackStatsService instance = PlaybackStatsService._();
  PlaybackStatsService._();

  Map<String, SongPlayStat> _stats = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 加载统计（幂等，不阻塞启动失败）
  Future<void> load() async {
    if (_loaded) return;
    _stats = await StorageService.loadPlayStats();
    _loaded = true;
    notifyListeners();
  }

  int countOf(String path) => _stats[path]?.playCount ?? 0;

  SongPlayStat? statOf(String path) => _stats[path];

  /// 计一次播放（由播放服务的 5 秒计时器调用）
  Future<void> recordStart(String path) async {
    final old = _stats[path] ?? const SongPlayStat();
    _stats[path] = old.copyWith(
      playCount: old.playCount + 1,
      lastPlayedAt: DateTime.now().toIso8601String(),
    );
    notifyListeners();
    await StorageService.savePlayStats(_stats);
  }

  /// 永久删除歌曲时清除统计；"仅移除库"不应调用本方法
  Future<void> removePaths(Iterable<String> paths) async {
    var changed = false;
    for (final p in paths) {
      if (_stats.remove(p) != null) changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await StorageService.savePlayStats(_stats);
  }

  @visibleForTesting
  void resetForTest() {
    _stats = {};
    _loaded = false;
  }
}

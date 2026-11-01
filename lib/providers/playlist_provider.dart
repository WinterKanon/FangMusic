import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../services/playlist_service.dart';
import '../services/storage_service.dart';

/// 用户歌单状态管理（v1.0 第三阶段）
///
/// 职责：持有用户歌单数据（自定义歌单列表），提供 CRUD，并负责持久化
/// （playlist_database.json，读写只经 [StorageService]）。
///
/// **"我的收藏"不在本类数据里**：它是系统虚拟歌单（固定第一位、
/// 不可删除、内容 = 全库 isFavorite 动态过滤），由抽屉与播放源
/// （[PlaylistService] 的 favorites 源）直接处理。
///
/// 纪律二：界面不直接碰数据文件，所有歌单操作通过本 Provider 发起。
/// 纪律三：所有写操作失败不致命（下次启动/下次写入会重建），不抛异常。
class PlaylistProvider extends ChangeNotifier {
  List<Playlist> _playlists = [];
  bool _loaded = false;

  /// 歌单 id 生成用的递增计数器（同一毫秒内连续创建也保证 id 唯一）
  static int _idCounter = 0;

  /// 用户自定义歌单列表（保持创建顺序；不包含"我的收藏"虚拟歌单）
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  /// 歌单是否已从磁盘加载（加载前 CRUD 操作仍可用，只是不落盘）
  bool get isLoaded => _loaded;

  /// 按 id 查找歌单（找不到返回 null）
  Playlist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 歌单总数（不含虚拟歌单）
  int get length => _playlists.length;

  //==================== 初始化 ====================

  /// 从磁盘加载歌单（幂等：只加载一次，之后是更新引用）。
  /// 失败不致命：返回空列表，继续运行（下次写入重建）。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _playlists = await StorageService.loadPlaylists();
    } catch (e) {
      debugPrint('[playlist] 加载歌单失败，使用空列表：$e');
      _playlists = [];
    }
    _syncToQueueService();
    notifyListeners();
  }

  /// 把最新歌单列表同步给播放队列服务（v1.1-3 修复）：
  /// PlaylistService 的池构建（_poolOf）按"歌单路径列表"生成，
  /// 若不同步，PlaylistService 里是启动时的旧 Playlist 对象
  /// （本类变更用 copyWith 替换元素，旧对象不含新歌/新路径）→
  /// 自定义歌单点歌后队列异常（顺序只剩当前歌 / 随机为空）。
  void _syncToQueueService() {
    PlaylistService.instance.updatePlaylists(_playlists);
  }

  //==================== CRUD ====================

  /// 创建歌单。名字规则由 [Playlist.validateName] 在 UI 层即时校验，
  /// 此处只做数据操作（非法名仍可创建，由 UI 保证不入此门）。
  /// 返回新歌单。
  Playlist createPlaylist(String name) {
    final playlist = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
      name: name.trim(),
      createTime: DateTime.now().toIso8601String(),
    );
    _playlists.add(playlist);
    _persist();
    _syncToQueueService();
    notifyListeners();
    return playlist;
  }

  /// 重命名歌单（UI 层已校验名字合法；找不到 id 则忽略）
  void renamePlaylist(String id, String newName) {
    final i = _indexOf(id);
    if (i < 0) return;
    _playlists[i] = _playlists[i].copyWith(name: newName.trim());
    _persist();
    _syncToQueueService();
    notifyListeners();
  }

  /// 删除歌单（"我的收藏"虚拟歌单不在此列，天然不可删）。
  /// 若删除的是**当前播放源歌单**，由调用方（抽屉）负责切回全部歌曲源。
  void deletePlaylist(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    _playlists.removeAt(i);
    _persist();
    _syncToQueueService();
    notifyListeners();
  }

  /// 把一首歌加入歌单（幂等：已在歌单中则忽略，避免重复行）。
  /// 返回是否真的加入（false = 已在歌单或歌单不存在）。
  bool addSongToPlaylist(String playlistId, String songFilePath) {
    final i = _indexOf(playlistId);
    if (i < 0) return false;
    if (_playlists[i].songFilePaths.contains(songFilePath)) return false;
    _playlists[i] = _playlists[i]
        .copyWith(songFilePaths: [..._playlists[i].songFilePaths, songFilePath]);
    _persist();
    _syncToQueueService();
    notifyListeners();
    return true;
  }

  /// 批量把多首歌加入歌单（v1.0 第四阶段："批量加入歌单"功能）。
  /// 幂等：已在歌单中的路径自动跳过；歌单不存在则直接返回 0。
  /// 返回实际新加入的数量（供 UI 提示）。
  int addSongsToPlaylist(String playlistId, List<String> songFilePaths) {
    final i = _indexOf(playlistId);
    if (i < 0) return 0;
    var added = 0;
    final existing = {..._playlists[i].songFilePaths};
    final toAdd = <String>[];
    for (final p in songFilePaths) {
      if (existing.contains(p)) continue; //已在歌单：跳过
      existing.add(p);
      toAdd.add(p);
      added++;
    }
    if (added == 0) return 0;
    _playlists[i] = _playlists[i].copyWith(
      songFilePaths: [..._playlists[i].songFilePaths, ...toAdd],
    );
    _persist();
    _syncToQueueService();
    notifyListeners();
    return added;
  }

  /// 从歌单移除一首歌（幂等：不在歌单中则忽略）。
  /// 返回是否真的移除（false = 不在歌单或歌单不存在）。
  bool removeSongFromPlaylist(String playlistId, String songFilePath) {
    final i = _indexOf(playlistId);
    if (i < 0) return false;
    if (!_playlists[i].songFilePaths.contains(songFilePath)) return false;
    _playlists[i] = _playlists[i].copyWith(
      songFilePaths: _playlists[i]
          .songFilePaths
          .where((p) => p != songFilePath)
          .toList(),
    );
    _persist();
    _syncToQueueService();
    notifyListeners();
    return true;
  }

  /// 从**所有**自定义歌单移除该歌曲（删除歌曲联动，需求 4）。
  /// 幂等：歌单中本就没有该歌则跳过。返回是否发生过移除。
  bool removeSongFromAllPlaylists(String songFilePath) {
    var changed = false;
    for (var i = 0; i < _playlists.length; i++) {
      if (_playlists[i].songFilePaths.contains(songFilePath)) {
        _playlists[i] = _playlists[i].copyWith(
          songFilePaths: _playlists[i]
              .songFilePaths
              .where((p) => p != songFilePath)
              .toList(),
        );
        changed = true;
      }
    }
    if (changed) {
      _persist();
      _syncToQueueService();
      notifyListeners();
    }
    return changed;
  }

  int _indexOf(String id) {
    for (var i = 0; i < _playlists.length; i++) {
      if (_playlists[i].id == id) return i;
    }
    return -1;
  }

  void _persist() {
    //异步写库；失败不致命（下次启动重新加载旧数据/下次写入重建）
    StorageService.savePlaylists(_playlists);
  }

  //==================== 测试 ====================

  /// 仅供测试：重置内部状态（不碰磁盘），可注入初始歌单列表
  @visibleForTesting
  void resetForTest({List<Playlist>? initial}) {
    _playlists = initial ?? [];
    _loaded = true;
  }
}

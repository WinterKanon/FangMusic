import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/list_sort_mode.dart';
import '../models/play_mode.dart';
import '../models/song.dart';
import '../models/sort_mode.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_scanner_service.dart';
import '../services/list_view_prefs_service.dart';
import '../services/playback_stats_service.dart';
import '../services/playlist_service.dart';
import '../services/song_sorter.dart';
import '../services/storage_service.dart';
import '../services/weight_config_service.dart';
import '../services/weight_service.dart';

/// 歌曲库状态管理（状态层）
///
/// 职责：持有歌曲库数据、加载、导入扫描、排序、收藏，并通知界面刷新。
/// 纪律二：界面不直接碰数据文件，所有操作通过本 Provider 发起。
class LibraryProvider extends ChangeNotifier {
  /// 当前音乐文件夹路径持久化 key（v1.0 第四阶段：主页下拉刷新用）
  static const _folderPathKey = 'music_folder_path';

  List<Song> _songs = [];
  bool _isLoading = true; //是否正在加载列表
  bool _isScanning = false; //是否正在扫描导入
  SortMode _sortMode = SortMode.addTime; //旧版排序（仅保留给兼容接口/测试）
  ListSortMode _listSortMode = ListSortMode.addTimeDesc; //v1.2 主页列表排序
  String? _folderPath; //最近一次成功扫描的文件夹路径（null = 尚未选过）

  /// 收藏歌曲路径集（v1.1 独立权威：`favorites.json`，按路径关联，与歌曲库
  /// 解耦——歌曲库损坏/被清空时收藏不丢失；顺序 = 收藏先后）
  List<String> _favoritePaths = [];

  List<Song> get songs => _songs;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  SortMode get sortMode => _sortMode;
  ListSortMode get listSortMode => _listSortMode;
  String? get folderPath => _folderPath;

  /// 收藏歌曲路径集（只读；顺序 = 收藏先后）
  List<String> get favoritePaths => List.unmodifiable(_favoritePaths);

  /// 从存储加载歌曲库，加载完成后通知界面
  ///
  /// 初始化顺序（阶段5 + v1.1 数据安全）：
  /// 1. 加载调权数值配置 + 排序偏好
  /// 2. 加载歌曲库
  /// 3. 按排序偏好重排 + 重写 sortNumber + 写库
  /// 4. **v1.1 收藏独立化**：加载收藏路径集并迁移旧 isFavorite 字段
  /// 5. **v1.1 权重独立化**：加载权威权重库（weights.json），再同步
  ///    权威权重引用 + 启动时 7 天回归（回归目标 = 基准权重）
  /// 6. 同步给播放服务 / 播放队列服务
  Future<void> loadSongs() async {
    _isLoading = true;
    notifyListeners();
    await WeightConfigService.instance.load();
    _folderPath = await _loadFolderPath();
    //v1.2：列表展示偏好（排序/自定义顺序）；旧 sort_mode 已在服务内迁移
    await ListViewPrefsService.instance.load();
    await PlaybackStatsService.instance.load();
    _listSortMode = ListViewPrefsService.instance.sortFor(
      ListViewPrefsService.keyHome,
    );
    final songs = await StorageService.loadSongs();
    _songs = songs;
    //v1.1-5：旧数据兼容——歌曲库已有歌曲但还没有"所选文件夹"记录时，
    //按歌曲所在目录补录，保证"所选文件夹管理"能看到历史导入的文件夹
    await StorageService.ensureFoldersForSongs(songs);
    _applySort(); //重排 + 重写 sortNumber + 写库
    //v1.1：收藏独立化——加载收藏路径集 + 迁移旧 isFavorite 字段 + 对齐
    await _syncFavorites();
    //v1.1：权重独立化——加载权威权重库（新歌迁移由 updateLibrary 完成）
    await WeightService.instance.load();
    //阶段4：同步权威权重引用（加权采样从这里读最新权重）
    WeightService.instance.updateLibrary(_songs);
    //阶段4：7 天回归（启动/每次加载库时检查，
    //>基准 且 7 天无增加/回归 → 回 5%；<基准 且 7 天无减少/回归 → 回 2%）
    await WeightService.instance.applySevenDayRegression();
    //同步歌曲库给播放服务（用于上一首/下一首定位）
    AudioPlaybackService.instance.updateLibrary(_songs);
    //v1.0 第四阶段：退出恢复——恢复上次播放的歌曲（只显示、不播放）
    await AudioPlaybackService.instance.restoreLastSongIfExists();
    //同步给播放队列服务（首次会初始化队列：读模式 + 队列文件）
    await PlaylistService.instance.init(_songs);
    _isLoading = false;
    notifyListeners();
  }

  /// v1.1 收藏独立化：
  /// 1. 加载收藏路径集（favorites.json，权威）
  /// 2. 迁移旧数据：songs.json 中 isFavorite=true 的路径合并进收藏集（一次）
  /// 3. 对齐：收藏集中的路径 → 歌曲对象 isFavorite=true（songs.json 同步写，
  ///    兼容旧版读取）
  Future<void> _syncFavorites() async {
    var paths = await StorageService.loadFavoritePaths();
    final set = paths.toSet();
    //1. 迁移旧数据（songs.json 的 isFavorite 字段 → 独立收藏集）
    var migrated = false;
    for (final s in _songs) {
      if (s.isFavorite && !set.contains(s.audioFilePath)) {
        set.add(s.audioFilePath);
        migrated = true;
      }
    }
    if (migrated) {
      paths = set.toList();
      await StorageService.saveFavoritePaths(paths);
    }
    //2. 对齐：收藏集中的路径 → 歌曲对象标记为收藏（并回写 songs.json 兼容）
    var changed = false;
    for (var i = 0; i < _songs.length; i++) {
      if (set.contains(_songs[i].audioFilePath) && !_songs[i].isFavorite) {
        _songs[i] = _songs[i].copyWith(isFavorite: true);
        changed = true;
      }
    }
    if (changed) await StorageService.saveSongs(_songs);
    _favoritePaths = paths;
    PlaylistService.instance.updateFavoriteOrder(_favoritePaths);
  }

  /// v1.2：主页列表排序（信息栏/排序面板调用）。
  /// 重排库 + 写库 + 同步服务；若当前是全部歌曲源且顺序播放，
  /// 同步重建播放队列（保持当前歌/进度，播放服务双播放器无感换池）。
  Future<void> setListSort(ListSortMode mode) async {
    if (mode == _listSortMode) return;
    _listSortMode = mode;
    await ListViewPrefsService.instance.setSort(
      ListViewPrefsService.keyHome,
      mode,
    );
    _applySort();
    WeightService.instance.updateLibrary(_songs);
    AudioPlaybackService.instance.updateLibrary(_songs);
    PlaylistService.instance.updateLibrary(_songs);
    if (PlaylistService.instance.source == PlaySource.allSongs &&
        PlaylistService.instance.mode == PlayMode.sequence) {
      PlaylistService.instance.applyListOrder(
        _songs.map((s) => s.audioFilePath).toList(),
        keepSongId: AudioPlaybackService.instance.currentSongId,
      );
    }
    notifyListeners();
  }

  /// v1.2：多选拖拽后的主页自定义顺序（同时切到 custom 排序）
  Future<void> setCustomOrder(List<String> order) async {
    await ListViewPrefsService.instance.setCustomOrder(
      ListViewPrefsService.keyHome,
      order,
    );
    _listSortMode = ListSortMode.custom;
    _applySort();
    WeightService.instance.updateLibrary(_songs);
    AudioPlaybackService.instance.updateLibrary(_songs);
    PlaylistService.instance.updateLibrary(_songs);
    if (PlaylistService.instance.source == PlaySource.allSongs &&
        PlaylistService.instance.mode == PlayMode.sequence) {
      PlaylistService.instance.applyListOrder(
        _songs.map((s) => s.audioFilePath).toList(),
        keepSongId: AudioPlaybackService.instance.currentSongId,
      );
    }
    notifyListeners();
  }

  /// 切换排序方式：重排列表 + 重写 sortNumber + 写库 + 持久化偏好，
  /// 并同步各服务（顺序/单曲循环队列按当前播放源池重建，保留当前歌；
  /// 歌单源下重建后仍是歌单内添加顺序，不受全库排序影响）
  Future<void> setSortMode(SortMode mode) async {
    if (mode == _sortMode) return;
    _sortMode = mode;
    await _sortMode.save();
    _applySort();
    //同步服务库引用（权重/播放用最新顺序与 sortNumber）
    WeightService.instance.updateLibrary(_songs);
    AudioPlaybackService.instance.updateLibrary(_songs);
    final queueMode = PlaylistService.instance.mode;
    if (queueMode == PlayMode.sequence || queueMode == PlayMode.repeatOne) {
      //顺序/单曲循环：按当前播放源池重建队列（keepSongId 保持当前歌高亮）
      //（allSongs = 新 sortNumber 全库；favorites = 收藏按新顺序过滤；
      //  playlist = 歌单添加顺序不变）
      PlaylistService.instance.rebuildQueue(
        keepSongId: AudioPlaybackService.instance.currentSongId,
      );
    } else {
      //随机模式：只同步库引用（队列是随机批次，与 sortNumber 无关）
      PlaylistService.instance.updateLibrary(_songs);
    }
    notifyListeners();
  }

  /// 按当前主页列表排序重排 + 重写 sortNumber(1..n) + 写库。
  void _applySort() {
    _songs = SongSorter.sort(
      _songs,
      _listSortMode,
      customOrder: ListViewPrefsService.instance.customOrderFor(
        ListViewPrefsService.keyHome,
      ),
      playCountOf: PlaybackStatsService.instance.countOf,
    );
    //重写 sortNumber（1..n），让顺序播放队列跟随新顺序
    for (var i = 0; i < _songs.length; i++) {
      _songs[i] = _songs[i].copyWith(sortNumber: i + 1);
    }
    //异步写库；失败不致命（下次启动重新排序）
    StorageService.saveSongs(_songs);
  }

  /// 按排序方式对歌曲列表排序（纯函数，便于测试）。
  /// 次级比较 sortNumber，保证相同键值时顺序稳定。
  @visibleForTesting
  static List<Song> sortBy(List<Song> input, SortMode mode) {
    final sorted = List.of(input);
    switch (mode) {
      case SortMode.addTime:
        sorted.sort((a, b) {
          final c = a.addTime.compareTo(b.addTime);
          return c != 0 ? c : a.sortNumber.compareTo(b.sortNumber);
        });
      case SortMode.name:
        sorted.sort((a, b) {
          final c = a.name.compareTo(b.name);
          return c != 0 ? c : a.sortNumber.compareTo(b.sortNumber);
        });
      case SortMode.duration:
        sorted.sort((a, b) {
          final c = a.duration.compareTo(b.duration);
          return c != 0 ? c : a.sortNumber.compareTo(b.sortNumber);
        });
    }
    return sorted;
  }

  /// 收藏/取消收藏：写库 + 同步服务库引用 + 收藏调权（阶段4 预留接口）
  /// 收藏 → +配置值；取消收藏 → -配置值（v1.0 第二阶段）
  ///
  /// v1.1：收藏**独立持久化**（favorites.json 权威，按路径），
  /// songs.json 的 isFavorite 字段同步写（兼容旧版读取）；
  /// 歌曲库暂无此歌（收藏页占位场景）时仅操作收藏集。
  Future<void> toggleFavorite(Song song) async {
    final i = _songs.indexWhere((s) => s.audioFilePath == song.audioFilePath);
    if (i < 0) {
      //歌曲库暂无此歌（如收藏页占位行）：仅更新独立收藏集
      if (_favoritePaths.contains(song.audioFilePath)) {
        _favoritePaths =
            _favoritePaths.where((p) => p != song.audioFilePath).toList();
        PlaylistService.instance.updateFavoriteOrder(_favoritePaths);
        notifyListeners();
        await StorageService.saveFavoritePaths(_favoritePaths);
      }
      return;
    }
    final newVal = !_songs[i].isFavorite;
    _songs[i] = _songs[i].copyWith(isFavorite: newVal);
    //更新独立收藏集（favorites.json 权威）
    if (newVal) {
      if (!_favoritePaths.contains(song.audioFilePath)) {
        _favoritePaths = [..._favoritePaths, song.audioFilePath];
      }
    } else {
      _favoritePaths =
          _favoritePaths.where((p) => p != song.audioFilePath).toList();
    }
    PlaylistService.instance.updateFavoriteOrder(_favoritePaths);
    notifyListeners();
    await StorageService.saveFavoritePaths(_favoritePaths);
    await StorageService.saveSongs(_songs);
    //同步服务库引用（保持歌曲对象一致）
    WeightService.instance.updateLibrary(_songs);
    AudioPlaybackService.instance.updateLibrary(_songs);
    //同步播放队列服务（v1.0 第三阶段：favorites 播放源 = 动态过滤，
    //收藏变化时队列同步增删；allSongs/playlist 源下仅更新引用）
    PlaylistService.instance.updateLibrary(_songs);
    //收藏调权（WeightService 按路径定位最新歌曲对象）
    await WeightService.instance.onFavorite(_songs[i], newVal);
  }

  /// 删除歌曲联动（v1.1-2 需求 4）——歌曲库与收藏部分：
  /// 从歌曲库移除该歌 + 重排编号 + 写库；从独立收藏集（favorites.json）移除 + 写库。
  /// （歌单 / 播放队列 / 权重由调用方分别同步；播放源队列经 [updateLibrary] 收尾过滤）
  Future<void> removeSongFromLibraryByPath(String path) async {
    if (!_songs.any((s) => s.audioFilePath == path)) return;
    _songs = _songs.where((s) => s.audioFilePath != path).toList();
    if (_favoritePaths.contains(path)) {
      _favoritePaths = _favoritePaths.where((p) => p != path).toList();
      PlaylistService.instance.updateFavoriteOrder(_favoritePaths);
      await StorageService.saveFavoritePaths(_favoritePaths);
    }
    //重排编号 + 重写 sortNumber，并 **await 落盘**（不能走 _applySort 的
    //unawaited 写库：调用方（删除歌曲）await 本方法返回后立即重新读取
    //磁盘验证，未落盘会读到旧库）
    _songs = SongSorter.sort(
      _songs,
      _listSortMode,
      customOrder: ListViewPrefsService.instance.customOrderFor(
        ListViewPrefsService.keyHome,
      ),
      playCountOf: PlaybackStatsService.instance.countOf,
    );
    for (var i = 0; i < _songs.length; i++) {
      _songs[i] = _songs[i].copyWith(sortNumber: i + 1);
    }
    await StorageService.saveSongs(_songs);
    notifyListeners();
  }

  /// 移除某个已选文件夹下的全部歌曲（v1.1-5 所选文件夹管理）：
  /// 只从 app 库/收藏移除并落盘，**不删除文件夹与音频文件**。
  /// 返回被移除的歌曲路径（供调用方清理歌单/队列/权重）。
  Future<List<String>> removeSongsUnderFolder(String folderPath) async {
    final base = StorageService.normalizeFolderPath(folderPath);
    final prefix = '$base/';
    final removed = _songs
        .where((s) => s.audioFilePath.startsWith(prefix))
        .map((s) => s.audioFilePath)
        .toList();
    //若最近扫描路径正是被删文件夹，清空它，避免下拉刷新又加回来
    if (StorageService.normalizeFolderPath(_folderPath ?? '') == base) {
      _folderPath = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_folderPathKey);
      } catch (_) {}
    }
    if (removed.isEmpty) return removed;
    final removedSet = removed.toSet();
    _songs =
        _songs.where((s) => !removedSet.contains(s.audioFilePath)).toList();
    _favoritePaths =
        _favoritePaths.where((p) => !removedSet.contains(p)).toList();
    PlaylistService.instance.updateFavoriteOrder(_favoritePaths);
    await StorageService.saveFavoritePaths(_favoritePaths);
    _songs = SongSorter.sort(
      _songs,
      _listSortMode,
      customOrder: ListViewPrefsService.instance.customOrderFor(
        ListViewPrefsService.keyHome,
      ),
      playCountOf: PlaybackStatsService.instance.countOf,
    );
    for (var i = 0; i < _songs.length; i++) {
      _songs[i] = _songs[i].copyWith(sortNumber: i + 1);
    }
    await StorageService.saveSongs(_songs);
    notifyListeners();
    return removed;
  }

  /// 扫描指定文件夹：交给 [AudioScannerService] 处理，完成后重新加载列表
  /// 返回扫描结果供界面弹提示
  Future<ScanResult> scanDirectory(
    String dirPath, {
    void Function(int current, int total)? onProgress,
  }) async {
    _isScanning = true;
    notifyListeners();
    try {
      final result = await AudioScannerService.scanDirectory(
        dirPath,
        onProgress: onProgress,
      );
      //记录并持久化文件夹路径（下拉刷新复用；失败不阻断扫描）
      _folderPath = dirPath;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_folderPathKey, dirPath);
      } catch (_) {}
      await loadSongs();
      return result;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// 下拉刷新（v1.0 第四阶段）：用最近一次选定的文件夹**重新扫描**，
  /// 反映该文件夹内歌曲的增减变化。返回 null 表示无法刷新
  /// （未选过文件夹 / 正在扫描中），否则返回扫描结果。
  Future<ScanResult?> refreshScan() async {
    final dir = _folderPath;
    if (dir == null || dir.isEmpty) return null;
    if (_isScanning) return null; //正在扫描：忽略重复触发
    return await scanDirectory(dir);
  }

  /// 读取持久化的音乐文件夹路径（不存在/失败返回 null）
  Future<String?> _loadFolderPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_folderPathKey);
    } catch (_) {
      return null;
    }
  }
}

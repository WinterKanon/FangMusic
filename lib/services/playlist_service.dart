import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/play_mode.dart';
import '../models/play_task.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'list_view_prefs_service.dart';
import 'playback_stats_service.dart';
import 'song_sorter.dart';
import 'storage_service.dart';
import 'weight_service.dart';

/// 播放源（v1.0 第三阶段）：当前播放队列基于哪个歌曲集合生成
///
/// - [allSongs]：全部歌曲（默认；池 = 全库按当前排序）
/// - [favorites]："我的收藏"虚拟歌单（池 = 全库 isFavorite 动态过滤）
/// - [playlist]：某个用户自定义歌单（池 = 歌单内歌曲添加顺序）
enum PlaySource {
  allSongs('全部歌曲'),
  favorites('我的收藏'),
  playlist('歌单');

  const PlaySource(this.label);

  /// 中文标签（调试/展示用）
  final String label;

  static const _prefKey = 'play_source';
  static const _prefPlaylistIdKey = 'play_source_playlist_id';

  /// 从偏好读取播放源（未知值回退全部歌曲）
  static Future<PlaySource> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PlaySource.values.firstWhere(
        (s) => s.name == prefs.getString(_prefKey),
        orElse: () => PlaySource.allSongs,
      );
    } catch (_) {
      return PlaySource.allSongs;
    }
  }

  /// 读取播放源关联的歌单 id（playlist 源用；读取失败返回 null）
  static Future<String?> loadPlaylistId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefPlaylistIdKey);
    } catch (_) {
      return null;
    }
  }

  /// 持久化播放源（+ 关联歌单 id，playlist 源才需要）
  Future<void> save({String? playlistId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, name);
      if (this == PlaySource.playlist) {
        await prefs.setString(_prefPlaylistIdKey, playlistId ?? '');
      }
    } catch (_) {
      //偏好写入失败不影响使用
    }
  }
}

/// 播放队列服务（服务层，自带状态广播，全局唯一实例）
///
/// 职责：
/// - 持有播放队列（任务列表 + 当前索引 + 播放模式 + **播放源**）
/// - 队列生成：顺序/单曲循环模式 = 当前播放源池按序；
///   普通随机 = 等权随机 50 首批次 + 滑动窗口追加/裁剪（上限 1000、同歌最多连续 2 次）；
///   加权随机 = 按歌曲权重 **CDF 采样** 生成批次（阶段4，权重取 [WeightService] 最新值）
/// - **播放源（v1.0 第三阶段）**：[PlaySource] 决定队列基于哪个歌曲池生成——
///   allSongs = 全库、favorites = 收藏动态过滤、playlist = 某歌单内歌曲；
///   歌单数据经 [updatePlaylists] 同步（由 PlaylistProvider 提供）；
///   当前播放源持久化，重启后恢复
/// - "添加下一首"：插入当前歌之后（已有"下一首"任务之后）
/// - 模式切换：重建队列 + 持久化
///
/// 队列持久化在 `home_play_task_database.json`，读写只经 [StorageService]。
/// 播放模式/播放源持久化在 SharedPreferences。
class PlaylistService extends ChangeNotifier {
  static final PlaylistService instance = PlaylistService._();
  PlaylistService._();

  /// 随机批次大小：每批生成 50 首
  static const _batchSize = 50;

  /// 队列任务总数上限
  static const _maxTasks = 1000;

  /// 滑动窗口：当前位置距批次末尾 ≤10 时追加下一批
  static const _refillThreshold = 10;

  /// "我的收藏"虚拟歌单固定 id（PlaySource.favorites 专用，不是 Playlist 对象）
  static const favoritesPlaylistId = '__favorites__';

  List<PlayTask> _tasks = [];
  List<Song> _library = [];
  List<Playlist> _playlists = [];
  List<String> _favoritePaths = []; //v1.2：收藏顺序（默认来源顺序）
  /// v1.0 第四阶段："添加下一首"插入任务后的播放器池同步回调
  /// （由 AudioPlaybackService 构造时注册，避免播放服务 → 队列服务的
  /// 直接依赖；单测不注册则跳过，保持纯逻辑可测）。
  /// [insertAt] = 任务在 app 队列中的插入位置（池按同一位置镜像插入，
  /// 保证"添加下一首"连排时的顺序与 app 内切歌一致——否则系统切歌
  /// 会逆序播放标记任务）。
  static void Function(int insertAt, String songFilePath)? onTaskInserted;

  /// v1.1-2 修复：队列任务移除后的播放器池同步回调（对称 [onTaskInserted]）。
  /// [removeAt] = 该任务**移除时**在 app 队列中的位置（移除多个副本时按
  /// 降序逐个回调，播放器池按同一位置降序移除即可保持镜像一致——
  /// 否则通知栏/锁屏的媒体队列里还残留已移除的歌，点击"下一首"会
  /// 播放本应已从队列移除的歌曲）。
  static void Function(int removeAt, String songFilePath)? onTaskRemoved;

  /// v1.2：列表排序/拖拽导致队列顺序变化后的回调。
  /// 播放服务据此用双播放器无感重建播放器池（不产生换源间隙）。
  static void Function()? onQueueReordered;

  int _currentIndex = -1; //-1 表示尚未定位过"当前播放"
  PlayMode _mode = PlayMode.sequence;
  PlaySource _source = PlaySource.allSongs;
  String? _sourcePlaylistId;
  bool _initialized = false;

  List<PlayTask> get tasks => List.unmodifiable(_tasks);
  PlayMode get mode => _mode;
  int get currentIndex => _currentIndex;

  /// 当前播放源（allSongs / favorites / playlist）
  PlaySource get source => _source;

  /// 当前播放源关联的歌单 id（source == playlist 时才有意义）
  String? get sourcePlaylistId => _sourcePlaylistId;

  /// 队列任务数
  int get length => _tasks.length;

  /// 当前歌曲库快照（供播放服务在自身库未同步时兜底找歌）
  List<Song> get librarySnapshot => List.unmodifiable(_library);

  /// 取第 index 个任务（越界返回 null）
  PlayTask? taskAt(int index) {
    if (index < 0 || index >= _tasks.length) return null;
    return _tasks[index];
  }

  //==================== 初始化与库同步 ====================

  /// 初始化：库加载完成后调用。
  /// 首次：读持久化模式 + 播放源 + 队列（为空则按当前源生成）；之后只更新库引用。
  Future<void> init(List<Song> library) async {
    _library = library;
    if (_initialized) return;
    _initialized = true;
    try {
      _mode = await PlayMode.load();
      await _loadSourcePrefs();
      final saved = await StorageService.loadPlayTasks();
      if (saved.isEmpty) {
        rebuildQueue();
      } else {
        _tasks = saved;
        _syncWithLibrary();
        if (_tasks.isEmpty) rebuildQueue();
      }
    } catch (e) {
      debugPrint('[queue] 初始化失败，按默认生成：$e');
      rebuildQueue();
    }
    notifyListeners();
  }

  /// 恢复持久化的播放源（playlist 源关联的歌单已不存在时回退全部歌曲）
  Future<void> _loadSourcePrefs() async {
    _source = await PlaySource.load();
    _sourcePlaylistId = await PlaySource.loadPlaylistId();
    if (_source == PlaySource.playlist) {
      final id = _sourcePlaylistId;
      if (id == null || id.isEmpty || !_playlists.any((p) => p.id == id)) {
        //歌单数据缺失/歌单已删除：回退全部歌曲并修正持久化
        _source = PlaySource.allSongs;
        _sourcePlaylistId = null;
        await _source.save();
      }
    }
  }

  /// 歌单数据同步（PlaylistProvider 加载/变更后调用）：
  /// 更新歌单引用；若当前源是 playlist 且该歌单被删除/路径变化，按池重建
  void updatePlaylists(List<Playlist> playlists) {
    _playlists = playlists;
    if (_source == PlaySource.playlist) {
      final id = _sourcePlaylistId;
      if (id == null || !_playlists.any((p) => p.id == id)) {
        //歌单已删除：回退全部歌曲源（并持久化修正）
        _source = PlaySource.allSongs;
        _sourcePlaylistId = null;
        unawaited(_source.save());
        rebuildQueue();
        return;
      }
      _syncWithLibrary();
    }
  }

  /// 歌曲库变化后同步（LibraryProvider 每次加载后调用）：
  /// 移除队列中已不在当前播放源池中的任务；若队列因此清空则按当前源重建
  void updateLibrary(List<Song> songs) {
    _library = songs;
    _syncWithLibrary();
  }

  /// v1.2：同步收藏顺序（默认 sourceOrder 用）
  void updateFavoriteOrder(List<String> paths) {
    _favoritePaths = List<String>.of(paths);
  }

  /// 当前播放源对应的歌曲路径池（有序）：
  /// - allSongs：全库（_library 已按当前排序，顺序 = sortNumber 顺序）
  /// - favorites：全库 isFavorite 过滤（动态）
  /// - playlist：歌单内添加顺序，且只保留库中仍存在的歌曲
  List<String> _poolOf(List<Song> library) {
    switch (_source) {
      case PlaySource.allSongs:
        return library.map((s) => s.audioFilePath).toList();
      case PlaySource.favorites:
        final byPath = {for (final s in library) s.audioFilePath: s};
        final favSongs = <Song>[
          for (final p in _favoritePaths)
            if (byPath[p] != null) byPath[p]!,
        ];
        //旧数据/尚未同步收藏顺序时回退到库内 isFavorite 过滤
        if (favSongs.isEmpty) {
          favSongs.addAll(library.where((s) => s.isFavorite));
        }
        return _sortedPaths(ListViewPrefsService.keyFavorites, favSongs);
      case PlaySource.playlist:
        final pl = _findPlaylist(_sourcePlaylistId);
        if (pl == null) return [];
        final byPath = {for (final s in library) s.audioFilePath: s};
        final plSongs = <Song>[
          for (final p in pl.songFilePaths)
            if (byPath[p] != null) byPath[p]!,
        ];
        return _sortedPaths(
            ListViewPrefsService.keyForPlaylist(pl.id), plSongs);
    }
  }

  /// 按列表偏好（排序/自定义顺序）输出路径（v1.2）
  List<String> _sortedPaths(String listKey, List<Song> songs) {
    final prefs = ListViewPrefsService.instance;
    final ordered = SongSorter.sort(
      songs,
      prefs.sortFor(listKey),
      customOrder: prefs.customOrderFor(listKey),
      playCountOf: PlaybackStatsService.instance.countOf,
    );
    return ordered.map((s) => s.audioFilePath).toList();
  }

  Playlist? _findPlaylist(String? id) {
    if (id == null) return null;
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _syncWithLibrary() {
    if (_tasks.isEmpty) return;
    final pool = _poolOf(_library);
    final poolSet = pool.toSet();
    //1. 移除池中已消失的任务（歌曲被移出歌单/取消收藏/从库删除）
    final before = _tasks.length;
    _tasks.removeWhere((t) => !poolSet.contains(t.songFilePath));
    //2. **集合源（playlist / favorites）下，追加池中新增的歌曲到队尾**
    //   （用户往歌单加歌/收藏新歌后，队列自动包含新歌；allSongs 源保持
    //   原行为——只移除不追加，避免扫描/排序静默改变队列）
    if (_source != PlaySource.allSongs) {
      final existing = _tasks.map((t) => t.songFilePath).toSet();
      final added = pool.where((p) => !existing.contains(p)).toList();
      if (added.isNotEmpty) {
        _tasks.addAll(added.map((p) => PlayTask(songFilePath: p)));
      }
    }
    if (_tasks.length != before) {
      if (_tasks.isEmpty) {
        _currentIndex = -1;
        rebuildQueue();
      } else {
        if (_currentIndex >= _tasks.length) {
          _currentIndex = _tasks.length - 1;
        }
        _persist();
      }
      notifyListeners();
    }
  }

  //==================== 播放源切换（v1.0 第三阶段）====================

  /// 切换播放源：设置新源（+ 关联歌单 id）→ 持久化 → 按新源重建队列。
  ///
  /// - [keepSongId] 默认 = 当前播放歌曲：若它在新源池中则作为 #1 保留
  ///   （不在新池中则不保留，从新池队首开始）
  /// - 重复切换到相同源（playlist 源且 id 相同）直接忽略，不重建
  Future<void> setPlaySource(
    PlaySource newSource, {
    String? playlistId,
  }) async {
    //相同源且（playlist 时 id 相同）：无变化，忽略
    if (newSource == _source &&
        (newSource != PlaySource.playlist ||
            playlistId == _sourcePlaylistId)) {
      return;
    }
    _source = newSource;
    _sourcePlaylistId = newSource == PlaySource.playlist ? playlistId : null;
    await _source.save(playlistId: _sourcePlaylistId);
    rebuildQueue(
      keepSongId: _currentSongPathOrNull(),
    );
  }

  /// 当前播放歌曲路径（未定位/越界时返回 null）
  String? _currentSongPathOrNull() {
    if (_currentIndex < 0 || _currentIndex >= _tasks.length) return null;
    return _tasks[_currentIndex].songFilePath;
  }

  //==================== 队列生成 ====================

  /// 重建队列（切换模式 / 播放源 / 初始化 / 库清空时）：
  /// - 顺序/单曲循环：当前播放源池按序（allSongs=全库排序、favorites=收藏过滤、
  ///   playlist=歌单添加顺序）
  /// - 随机：批次生成（keepSongId 作为 #1）
  void rebuildQueue({String? keepSongId}) {
    final pool = _poolOf(_library);
    if (pool.isEmpty) {
      _tasks = [];
      _currentIndex = -1;
      notifyListeners();
      return;
    }
    if (_mode == PlayMode.sequence || _mode == PlayMode.repeatOne) {
      _tasks = pool
          .map((path) => PlayTask(songFilePath: path))
          .toList();
      _currentIndex = keepSongId != null
          ? _tasks.indexWhere((t) => t.songFilePath == keepSongId)
          : 0;
      if (_currentIndex < 0) _currentIndex = 0;
    } else {
      //随机（realRandom 等权 / weightedRandom 按权重 CDF 采样，阶段4）
      _tasks = _generateRandomBatch(keepSongId: keepSongId);
      _currentIndex = _tasks.isEmpty ? -1 : 0;
    }
    _persist();
    notifyListeners();
  }

  /// 生成一批随机任务（50 首；单曲库允许连播）
  ///
  /// - [keepSongId] 非空时作为批次第一首（切换模式时保留当前歌）
  /// - [existing] 传入已有队列尾部，用于滑动窗口追加时避免与末尾连续 3 次
  /// - 采样算法：普通随机 = 等权；加权随机 = CDF 累积权重（阶段4）
  /// - 候选池 = 当前播放源池（歌单/收藏源下随机只在源内进行）
  List<PlayTask> _generateRandomBatch({
    String? keepSongId,
    List<PlayTask> existing = const [],
  }) {
    final pool = _poolOf(_library);
    if (pool.isEmpty) return [];
    final result = <PlayTask>[];
    if (keepSongId != null && pool.contains(keepSongId)) {
      result.add(PlayTask(songFilePath: keepSongId));
    }

    //最近两首（用于"同歌最多连续 2 次"）：从已有队列尾部或 keepSongId 继承
    String? last1, last2;
    if (existing.isNotEmpty) {
      last1 = existing.last.songFilePath;
      if (existing.length >= 2) {
        last2 = existing[existing.length - 2].songFilePath;
      }
    } else if (result.isNotEmpty) {
      last1 = result.first.songFilePath;
    }

    final rng = Random();
    var guard = 0; //防止意外死循环
    while (result.length < _batchSize && pool.isNotEmpty && guard++ < 5000) {
      //候选池排除"将造成连续 3 次"的歌（last1==last2==候选 时排除）
      var candidates =
          pool.where((p) => !(p == last1 && p == last2)).toList();
      if (candidates.isEmpty) {
        //曲库只有 1 首：允许连续播放
        candidates = List.of(pool);
      }
      //加权随机：按权重 CDF 采样；普通随机：等权
      final pick = _mode == PlayMode.weightedRandom
          ? _weightedPick(candidates)
          : candidates[rng.nextInt(candidates.length)];
      result.add(PlayTask(songFilePath: pick));
      last2 = last1;
      last1 = pick;
    }
    return result;
  }

  /// 加权随机采样（CDF 累积权重法）：
  /// totalWeight = Σ候选权重；rand ∈ [0, totalWeight)；
  /// 遍历候选累加权重，首个累加和 ≥ rand 的候选即选中。
  ///
  /// 权重取 [WeightService] 的**最新值**（权威引用）；
  /// 总权重 ≤0 时退化为等权随机。
  String _weightedPick(List<String> candidates) {
    double total = 0;
    for (final c in candidates) {
      total += _weightOf(c);
    }
    if (total <= 0) return candidates[Random().nextInt(candidates.length)];
    final rng = Random();
    var rand = rng.nextDouble() * total;
    for (final c in candidates) {
      rand -= _weightOf(c);
      if (rand <= 0) return c;
    }
    return candidates.last; //浮点误差兜底
  }

  /// 查某首歌的最新权重（走 WeightService 权威库；找不到回退默认 100）
  double _weightOf(String audioFilePath) {
    return WeightService.instance.weightOf(audioFilePath) ?? 100.0;
  }

  /// 随机模式滑动窗口：当前位置距末尾 ≤10 时追加一批（上限 1000）
  void maybeRefill() {
    if (_mode != PlayMode.realRandom && _mode != PlayMode.weightedRandom) {
      return;
    }
    if (_tasks.length >= _maxTasks) return;
    if (_tasks.length - _currentIndex > _refillThreshold) return;
    final more = _generateRandomBatch(existing: _tasks);
    if (more.isEmpty) return;
    final remaining = _maxTasks - _tasks.length;
    _tasks.addAll(more.take(remaining));
    _persist();
    notifyListeners();
  }

  //==================== 取下一首 / 上一首 ====================

  /// 取下一首并推进当前索引。
  ///
  /// 随机模式边界（队列末尾）：重排全新批次，**不把刚播完的当前歌
  /// 强制放 #1**（否则会立刻再播一遍），并保留全部未播放的
  /// "下一首"任务。顺序模式边界：回到队首。
  PlayTask? nextTask() {
    if (_tasks.isEmpty) return null;
    if (_currentIndex < 0) {
      //未播放过 / 队首正在播放的任务被移除（v1.1-2）：
      //从**队首**开始，而不是队首之后（否则会跳过第一首）
      _currentIndex = 0;
      _clearNextFlag(0); //队首若是"下一首"任务则已消费
      notifyListeners();
      return _tasks[0];
    }
    final idx = _currentIndex + 1;
    if (idx >= _tasks.length) {
      if (_mode == PlayMode.realRandom || _mode == PlayMode.weightedRandom) {
        //1. 收集全部未播放的"下一首"任务（重排后保留，不随重排丢失）
        final nextSongs = _collectNextSongs();
        //2. 生成全新随机批次：当前歌已播完，不强制作 #1
        //   （existing 延续"同歌最多连续 2 次"限制）
        _tasks = _generateRandomBatch(existing: _tasks);
        _currentIndex = _tasks.isEmpty ? -1 : 0;
        //3. 保留"下一首"任务（插到新批次队首之后）
        if (_currentIndex >= 0 && nextSongs.isNotEmpty) {
          var insertAt = _currentIndex + 1;
          for (final s in nextSongs) {
            if (insertAt <= _tasks.length) {
              _tasks.insert(
                insertAt++,
                PlayTask(songFilePath: s, isNextSong: true),
              );
            }
          }
        }
        _persist();
        notifyListeners();
        return _tasks.isEmpty ? null : _tasks[0];
      }
      _currentIndex = 0;
      _clearNextFlag(0); //回到队首，若队首是"下一首"任务则已消费
      notifyListeners();
      return _tasks[0];
    }
    _currentIndex = idx;
    _clearNextFlag(idx); //任务被播放，"下一首"标记消费清除
    notifyListeners();
    maybeRefill();
    return _tasks[idx];
  }

  /// 取上一首并回退当前索引（队首回到末尾）
  PlayTask? previousTask() {
    if (_tasks.isEmpty) return null;
    if (_currentIndex < 0) _currentIndex = 0;
    final idx = _currentIndex - 1;
    if (idx < 0) {
      _currentIndex = _tasks.length - 1;
      _clearNextFlag(_currentIndex); //任务被播放，清除标记
      notifyListeners();
      return _tasks.last;
    }
    _currentIndex = idx;
    _clearNextFlag(idx); //任务被播放，清除标记
    notifyListeners();
    return _tasks[idx];
  }

  /// 定位当前索引到指定位置（队列页点击用）
  void moveToIndex(int index) {
    if (index < 0 || index >= _tasks.length) return;
    _currentIndex = index;
    _clearNextFlag(index); //任务被播放，清除标记
    notifyListeners();
  }

  /// 播放某歌时定位队列位置。
  ///
  /// **随机模式**：主页每次点击非当前歌曲都会**重建随机批次**，
  /// 点击的歌曲排到队首（#1），并保留"下一首"标记任务在 #1 之后
  /// （与切模式 / 随机边界重排行为一致）。
  /// **顺序/单曲循环模式**：定位到已有位置，不在队列则追加末尾。
  void moveTo(String songFilePath) {
    //随机模式：点击非当前歌曲 → 重排批次，点击的歌排 #1
    if (_mode == PlayMode.realRandom || _mode == PlayMode.weightedRandom) {
      //收集全部未播放的"下一首"任务，重排后保留
      final nextSongs = _collectNextSongs();
      rebuildQueue(keepSongId: songFilePath);
      //保留"下一首"任务（插到当前歌之后）
      if (nextSongs.isNotEmpty) {
        var insertAt = _currentIndex + 1;
        for (final s in nextSongs) {
          if (insertAt <= _tasks.length) {
            _tasks.insert(
              insertAt++,
              PlayTask(songFilePath: s, isNextSong: true),
            );
          }
        }
        _persist();
      }
      notifyListeners();
      return;
    }
    //顺序/单曲循环：定位已有位置或追加末尾
    final idx = _tasks.indexWhere((t) => t.songFilePath == songFilePath);
    if (idx >= 0) {
      _currentIndex = idx;
      _clearNextFlag(idx); //任务被播放，清除标记
    } else {
      _tasks.add(PlayTask(songFilePath: songFilePath));
      _currentIndex = _tasks.length - 1;
      _persist();
    }
    notifyListeners();
  }

  //==================== 添加下一首 ====================

  /// "添加下一首"：插入当前歌之后；
  /// 若当前歌后已有"下一首"任务，新任务插在它们之后（保持连续），
  /// 未播放过任何歌时放队首。
  void addNextSong(String songFilePath) {
    int insertAt;
    if (_currentIndex < 0) {
      insertAt = 0;
    } else {
      insertAt = _currentIndex + 1;
      while (insertAt < _tasks.length && _tasks[insertAt].isNextSong) {
        insertAt++;
      }
    }
    _tasks.insert(
      insertAt,
      PlayTask(songFilePath: songFilePath, isNextSong: true),
    );
    _persist();
    notifyListeners();
    //v1.0 第四阶段修复：通知播放服务把新任务**同步插入播放器池**
    //（当前歌之后）——否则系统"下一首"在旧池步进会跳过刚添加的歌
    //（播放层面）。用回调解耦（单测环境不注册 → 不触发播放器初始化）。
    onTaskInserted?.call(insertAt, songFilePath);
  }

  //==================== 移除任务（v1.1-2）====================

  /// 播放队列页"减号"移除单个任务（需求 7）：
  /// - 移除**当前播放位置之前**的任务：当前索引同步前移
  /// - 移除**正在播放的任务**：**继续播放当前**（播放器池不动），
  ///   索引回退一位——播完自动切下一首（队首任务被移除 → -1，
  ///   [nextTask] 会重置到队首，被删歌不会重播）
  void removeTaskAt(int index) {
    if (index < 0 || index >= _tasks.length) return;
    final removedPath = _tasks[index].songFilePath; //回调用
    if (index < _currentIndex) {
      _currentIndex -= 1;
    } else if (index == _currentIndex) {
      _currentIndex = index - 1; //播放中任务被移除：回退一位（允许 -1）
    }
    _tasks.removeAt(index);
    if (_tasks.isEmpty) {
      _currentIndex = -1;
    } else if (_currentIndex >= _tasks.length) {
      _currentIndex = _tasks.length - 1;
    }
    _persist();
    notifyListeners();
    //播放器池同步（通知栏/锁屏媒体队列移除同位置任务）
    onTaskRemoved?.call(index, removedPath);
  }

  /// 删除歌曲联动（需求 4）：移除队列中该歌的**全部**任务
  /// （含"添加下一首"标记任务）。
  ///
  /// 正在播放该歌：**保留播放**（播放器池不动，音频已加载不受影响），
  /// 索引回退一位 → 播完自动切下一首；若该歌在当前位置之前有副本，
  /// 一并按移除数量前移索引，保证播完后的下一首不跳歌。
  void removeTaskByPath(String songFilePath) {
    if (_tasks.isEmpty) return;
    final ci = _currentIndex;
    final isCurrent =
        ci >= 0 && ci < _tasks.length && _tasks[ci].songFilePath == songFilePath;
    var removedBefore = 0; //当前位置之前被移除的副本数
    //从后往前移除：前面的索引不受影响，回调位置 = 移除时队列中的位置
    for (var i = _tasks.length - 1; i >= 0; i--) {
      if (_tasks[i].songFilePath == songFilePath) {
        _tasks.removeAt(i);
        if (i < ci) removedBefore++;
        //播放器池同步（降序移除，镜像保持一致）
        onTaskRemoved?.call(i, songFilePath);
      }
    }
    if (_tasks.isEmpty) {
      _currentIndex = -1;
    } else if (isCurrent) {
      //当前歌被删除：回退到"前一个未删除任务"，播完从它后面取下一首
      _currentIndex = ci - removedBefore - 1;
      if (_currentIndex < -1) _currentIndex = -1;
    } else {
      _currentIndex = ci - removedBefore;
    }
    if (_currentIndex >= _tasks.length) _currentIndex = _tasks.length - 1;
    _persist();
    notifyListeners();
  }

  //==================== 列表排序同步（v1.2）====================

  /// 手动点击非当前歌曲（顺序模式）：以点击歌为首，重排基础顺序，
  /// “下一首”任务按原顺序紧随其后；其余歌曲按当前列表顺序环绕。
  void rebuildQueueStartingAt(String songFilePath) {
    if (_mode != PlayMode.sequence) return;
    final base = _poolOf(_library);
    if (base.isEmpty) return;
    final i = base.indexOf(songFilePath);
    final rotated = i < 0
        ? [songFilePath, ...base]
        : [...base.sublist(i), ...base.sublist(0, i)];
    final nextTasks = _tasks
        .where((t) => t.isNextSong)
        .map((t) => PlayTask(
              songFilePath: t.songFilePath,
              isNextSong: true,
            ))
        .toList();
    _tasks = [
      PlayTask(songFilePath: rotated.first),
      ...nextTasks,
      for (final path in rotated.skip(1)) PlayTask(songFilePath: path),
    ];
    _currentIndex = 0;
    _persist();
    notifyListeners();
  }

  /// 把**顺序播放**队列按当前列表顺序重排（预设排序/拖拽自定义顺序共用）。
  ///
  /// - 仅 `sequence` 模式生效；随机批次/单曲循环不改队列；
  /// - [orderedPaths] 为列表展示顺序（不在当前源池的路径忽略，缺失歌曲追加到末尾）；
  /// - 保留未播放的"下一首"任务：按原相对顺序插到当前歌之后（不随排序丢失）；
  /// - 当前歌按路径重新定位，保持高亮与后续切歌语义；
  /// - 完成后回调 [onQueueReordered]，由播放服务用双播放器无感换池。
  void applyListOrder(List<String> orderedPaths, {String? keepSongId}) {
    if (_mode != PlayMode.sequence) return;
    final pool = _poolOf(_library);
    if (pool.isEmpty) return;
    final poolSet = pool.toSet();
    final base = <PlayTask>[];
    final seen = <String>{};
    void add(String path) {
      if (poolSet.contains(path) && seen.add(path)) {
        base.add(PlayTask(songFilePath: path));
      }
    }

    for (final path in orderedPaths) {
      add(path);
    }
    for (final path in pool) {
      add(path);
    }
    if (base.isEmpty) return;

    final currentPath = keepSongId ?? _currentSongPathOrNull();
    var index = currentPath == null
        ? -1
        : base.indexWhere((t) => t.songFilePath == currentPath);
    if (index < 0) index = 0;

    //保留"下一首"标记任务（含重复），插到当前歌之后
    final nextTasks = _tasks
        .where((t) => t.isNextSong && poolSet.contains(t.songFilePath))
        .toList();
    var insertAt = index + 1;
    for (final t in nextTasks) {
      base.insert(
        insertAt++,
        PlayTask(songFilePath: t.songFilePath, isNextSong: true),
      );
    }

    _tasks = base;
    _currentIndex = index;
    _persist();
    notifyListeners();
    onQueueReordered?.call();
  }

  //==================== 模式切换 ====================

  /// 切换播放模式：持久化 + 按模式处理队列
  ///
  /// - 切到**单曲循环**：保留切换前的队列排列与当前位置
  ///   （从顺序切过来显示顺序排列、从随机切过来显示随机排列），仅切换模式
  /// - 切到**顺序/随机**：重建队列（随机 → 批次重建，当前歌作 #1；
  ///   顺序 → 当前播放源池按序），并保留"下一首"任务
  /// - 切到**加权随机**：额外触发 7 天回归 + 清空衰减周期计数（阶段4）
  Future<void> setMode(PlayMode newMode) async {
    if (newMode == _mode) return;
    final cur =
        _currentIndex >= 0 && _currentIndex < _tasks.length
            ? _tasks[_currentIndex].songFilePath
            : null;
    //收集全部未播放的"下一首"任务，切换模式后保留
    final nextSongs = _collectNextSongs();
    _mode = newMode;
    await _mode.save();
    //切到加权随机：清空周期播放计数 + 触发 7 天回归（阶段4）
    if (newMode == PlayMode.weightedRandom) {
      WeightService.instance.resetDecayCounts();
      await WeightService.instance.applySevenDayRegression();
    }
    //单曲循环：保留切换前的队列排列与当前位置
    //（从顺序播放切过来显示顺序排列、从随机切过来显示随机排列），
    //仅切换模式，不重建队列
    if (newMode == PlayMode.repeatOne) {
      notifyListeners();
      return;
    }
    rebuildQueue(keepSongId: cur);
    //重新插入"下一首"任务（当前歌之后）
    if (cur != null && _currentIndex >= 0 && nextSongs.isNotEmpty) {
      var insertAt = _currentIndex + 1;
      for (final s in nextSongs) {
        if (insertAt <= _tasks.length) {
          _tasks.insert(
            insertAt++,
            PlayTask(songFilePath: s, isNextSong: true),
          );
        }
      }
      _persist();
      notifyListeners();
    }
  }

  //==================== 工具 ====================

  /// 收集队列中全部未播放的"下一首"任务路径
  /// （队列重排/切模式时保留，避免插队任务随重排丢失）
  List<String> _collectNextSongs() {
    return _tasks
        .where((t) => t.isNextSong)
        .map((t) => t.songFilePath)
        .toList();
  }

  /// 任务被播放后清除"下一首"标记（该任务已被消费，
  /// 不再是"插队"状态，恢复为普通队列成员）
  void _clearNextFlag(int index) {
    if (index < 0 || index >= _tasks.length) return;
    if (!_tasks[index].isNextSong) return;
    final t = _tasks[index];
    _tasks[index] = PlayTask(songFilePath: t.songFilePath);
    _persist();
  }

  /// 仅供测试：重置内部状态（不碰磁盘，可指定模式/播放源/歌单数据）
  @visibleForTesting
  void resetForTest({
    PlayMode mode = PlayMode.sequence,
    PlaySource source = PlaySource.allSongs,
    String? sourcePlaylistId,
    List<Playlist> playlists = const [],
  }) {
    _tasks = [];
    _library = [];
    _playlists = playlists;
    _favoritePaths = [];
    _currentIndex = -1;
    _mode = mode;
    _source = source;
    _sourcePlaylistId = sourcePlaylistId;
    _initialized = false;
  }

  void _persist() {
    //异步写队列；失败不致命（下次启动可重建）
    StorageService.savePlayTasks(_tasks);
  }
}

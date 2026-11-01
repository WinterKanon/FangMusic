import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/play_mode.dart';
import '../models/song.dart';
import '../models/weight_behavior.dart';
import 'music_audio_handler.dart';
import 'playback_stats_service.dart';
import 'playlist_service.dart';
import 'sleep_timer_service.dart';
import 'weight_service.dart';

/// 播放控制服务（服务层，自带状态广播，全局唯一实例）
///
/// 职责：
/// - 播放/暂停、进度、上一首/下一首（切歌走播放队列 [PlaylistService]）
/// - 播放完成按模式分流：单曲循环 → 重播当前歌；其余 → 下一首
/// - 播放失败兜底（文件被移动/删除等，自动跳过失效任务）
/// - 阶段4 权重接入：手动点击/单曲循环重播/10 秒内快切调权、
///   加权随机模式播放衰减
/// - v1.2 双播放器无缝换源：主/备两个 AudioPlayer，模式切换时备播放器
///   静音预加载新池并对齐进度，随后瞬时交换（无静音间隔）；通知栏由
///   [MusicAudioHandler]（audio_service）统一驱动，不随交换中断。
///
/// 全局唯一实例：任何页面都访问同一个实例，跨页面共享播放状态。
class AudioPlaybackService extends ChangeNotifier {
  static final AudioPlaybackService instance = AudioPlaybackService._();

  /// 上次播放歌曲路径持久化 key（v1.0 第四阶段：退出恢复）
  static const _currentSongPathKey = 'current_song_path';

  AudioPlaybackService._() {
    _bindPlayer(_activePlayer);
    //双播放器必须自行管理音频会话（just_audio 多播放器约定）：
    //两个播放器都关闭自动激活，由本服务统一 setActive，否则第二
    //播放器 play() 会卡在 audio_session 激活上（实测卡死）。
    unawaited(_configureAudioSession());
    //注册"添加下一首"同步回调（PlaylistService 侧解耦调用）
    PlaylistService.onTaskInserted = onTaskInserted;
    //注册"移除队列任务"同步回调（v1.1-2 修复：通知栏/锁屏媒体队列
    //需与 app 队列同步移除，否则系统"下一首"会播放已移除的歌）
    PlaylistService.onTaskRemoved = onTaskRemoved;
    //v1.2：列表排序/拖拽同步队列后，用双播放器无感重建播放器池
    PlaylistService.onQueueReordered = onQueueOrderChanged;
    //v1.2 睡眠定时：注入暂停/播放态查询
    SleepTimerService.instance.pausePlayer = pause;
    SleepTimerService.instance.isPlaying = () => _isPlaying;
    //睡眠定时到点（播完当前歌）时，按剩余时长精确安排暂停，避免
    //播放器原生自动连播抢在前面导致“下一首继续播、倒计时停在0:00”
    SleepTimerService.instance.addListener(_onSleepTimerChanged);
  }

  void _onSleepTimerChanged() {
    final sleep = SleepTimerService.instance;
    if (!sleep.pendingPause) {
      _sleepEndTimer?.cancel();
      _sleepEndTimer = null;
      return;
    }
    if (!_isPlaying || _currentSong == null) return;
    if (_sleepEndTimer?.isActive ?? false) return;
    final total = _duration;
    if (total <= Duration.zero) return;
    final remain = total - _player.position;
    if (remain <= Duration.zero) return;
    final realRemain = Duration(
      milliseconds: (remain.inMilliseconds / _playbackSpeed)
          .round()
          .clamp(0, 1 << 31)
          .toInt(),
    );
    final delay = realRemain - const Duration(milliseconds: 150);
    _sleepEndTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () async {
        _sleepEndTimer = null;
        if (!SleepTimerService.instance.pendingPause || !_isPlaying) return;
        if (SleepTimerService.instance.consumePendingPause()) {
          await pause();
        }
      },
    );
  }

  /// 队列顺序变化（列表排序/拖拽同步）后调用：按新 tasks 顺序重建播放池。
  /// 复用模式切换的双播放器预加载/交换，保持当前歌与进度、无静音间隙。
  Future<void> onQueueOrderChanged() {
    //未选歌或播放器尚未加载音源（退出恢复态）：队列已更新，等下次播放再建池
    if (_currentSong == null || _player.audioSource == null) {
      return Future<void>.value();
    }
    final next = _modeSwitchChain.then(
      (_) => _applyModeChanged(force: true),
    );
    final guarded = next.catchError((Object e) {
      debugPrint('[playback] 队列顺序同步异常（忽略）：$e');
    });
    _modeSwitchChain = guarded;
    return guarded;
  }

  /// 双播放器（v1.2）：_activePlayer 出声/被 UI 监听；_standbyPlayer 用于
  /// 静音预加载新队列，加载完成后交换，实现模式切换零静音。
  /// handleAudioSessionActivation=false：多播放器下由服务统一管理会话。
  final AudioPlayer _playerA =
      AudioPlayer(handleAudioSessionActivation: false);
  final AudioPlayer _playerB =
      AudioPlayer(handleAudioSessionActivation: false);
  late AudioPlayer _activePlayer = _playerA;
  late AudioPlayer _standbyPlayer = _playerB;
  AudioPlayer get _player => _activePlayer;

  bool _sessionActive = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  /// 初始化音频会话：只在启动时激活一次；监听来电等中断自动暂停。
  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _interruptionSub =
          session.interruptionEventStream.listen((event) {
        if (event.begin && _isPlaying) {
          unawaited(pause());
        }
      });
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (_isPlaying) unawaited(pause());
      });
    } catch (e) {
      debugPrint('[playback] 音频会话初始化失败（忽略）：$e');
    }
  }

  /// 确保会话已激活后再播放（多播放器约定：会话由服务统一管理）
  /// 确保会话已激活后播放（多播放器约定：会话由服务统一管理）。
  /// **不 await play()**：just_audio 的 play() Future 要到暂停/播完才完成，
  /// 等待会让切歌/双播放器交换永远卡住。
  void _startPlayer(AudioPlayer player) {
    unawaited(() async {
      if (!_sessionActive) {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
          _sessionActive = true;
        } catch (e) {
          debugPrint('[playback] 激活音频会话失败（继续尝试播放）：$e');
        }
      }
      try {
        await player.play();
      } catch (e) {
        debugPrint('[playback] 播放启动失败（忽略）：$e');
      }
    }());
  }

  final List<StreamSubscription<dynamic>> _playerSubs = [];

  List<Song> _library = []; //歌曲库（由主页加载后同步进来，用于按路径找歌）
  List<Song> _pool = []; //当前播放器已加载的媒体队列（方案 A）
  Song? _currentSong; //当前歌曲（null 表示未选过任何歌）
  bool _isPlaying = false; //是否正在播放
  Duration _position = Duration.zero; //当前播放位置
  Duration _duration = Duration.zero; //当前歌曲总时长
  DateTime? _songStartTime; //当前歌曲开始播放的时刻（阶段4：10 秒快切判定）
  PlayMode? _lastMode; //最近一次 onModeChanged 处理的模式（用于判断池形状是否变化）

  /// v1.2 播放次数：当前歌是否已计过、5 秒计时器
  Timer? _playCountTimer;
  bool _countedCurrentSong = false;

  /// v1.2 倍速播放（切换歌曲/换源后保持）
  double _playbackSpeed = 1.0;

  /// v1.2 睡眠定时“播完当前歌”的精确结束计时器
  Timer? _sleepEndTimer;

  /// 通知栏媒体队列/媒体项缓存（v1.2：audio_service）
  List<MediaItem> _mediaQueue = [];
  bool _notificationQueueDirty = true;
  MusicAudioHandler? _boundHandler;

  /// 模式切换串行链：快速连续切换时按调用顺序执行换源。
  Future<void> _modeSwitchChain = Future<void>.value();

  Song? get currentSong => _currentSong;
  String? get currentSongId => _currentSong?.audioFilePath;
  bool get isPlaying => _isPlaying;
  bool get hasSong => _currentSong != null;
  Duration get position => _position;
  Duration get duration => _duration;
  double get playbackSpeed => _playbackSpeed;

  /// 绑定/切换当前出声的播放器：取消旧监听、监听新播放器的状态流。
  /// 双播放器交换后调用，保证 UI/权重/通知只跟随当前主播放器。
  void _bindPlayer(AudioPlayer player) {
    for (final sub in _playerSubs) {
      unawaited(sub.cancel());
    }
    _playerSubs.clear();
    //监听底层播放器的状态流，广播给 UI
    _playerSubs.add(player.playingStream.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        _schedulePlayCount();
      } else {
        _playCountTimer?.cancel();
        _playCountTimer = null;
      }
      notifyListeners();
      _publishNotificationState();
    }));
    //当前播放位置（驱动进度条实时更新；通知栏播放状态由系统按
    //updatePosition/updateTime 自行插值，无需每 200ms 推送一次）
    _playerSubs.add(player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    }));
    //歌曲总时长（加载完成后更新）
    _playerSubs.add(player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    }));
    //播放完成：按模式分流（单曲循环重播 / 其余下一首）
    _playerSubs.add(player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
        notifyListeners();
        _onSongCompleted();
      }
      _publishNotificationState();
    }));
    //队列索引变化：非代码驱动切歌（播放器自动连播）时同步当前歌与游标
    _playerSubs.add(player.currentIndexStream.listen((index) {
      _onPlayerIndexChanged(index);
      _publishNotificationState();
    }));
  }

  /// v1.2：新歌/重播时重置计数状态
  void _markNewPlaySession() {
    _countedCurrentSong = false;
    _playCountTimer?.cancel();
    _playCountTimer = null;
  }

  /// v1.2：连续播放 ≥5 秒计 1 次；暂停/切歌取消计时，同一次播放不重复
  void _schedulePlayCount() {
    if (!_isPlaying ||
        _currentSong == null ||
        _countedCurrentSong ||
        (_playCountTimer?.isActive ?? false)) {
      return;
    }
    final path = _currentSong!.audioFilePath;
    _playCountTimer = Timer(const Duration(seconds: 5), () {
      _playCountTimer = null;
      if (_isPlaying && _currentSong?.audioFilePath == path) {
        _countedCurrentSong = true;
        unawaited(PlaybackStatsService.instance.recordStart(path));
      }
    });
  }

  /// 由主页在歌曲库加载/变化后调用，同步歌曲库（用于按路径找歌）
  void updateLibrary(List<Song> songs) {
    _library = songs;
  }

  /// 重建通知栏媒体队列缓存（池变化后调用，不做逐帧重建）
  void _rebuildMediaQueue() {
    _mediaQueue = [
      for (var i = 0; i < _pool.length; i++)
        MediaItem(
          id: '${_pool[i].audioFilePath}#$i',
          title: _pool[i].name,
          album: '',
          artist: '本地音乐',
          displaySubtitle: '本地音乐',
          duration: Duration(milliseconds: _pool[i].duration),
        ),
    ];
    _notificationQueueDirty = true;
  }

  MediaItem? get _currentMediaItem {
    final idx = _player.currentIndex ?? 0;
    if (_mediaQueue.isEmpty || idx < 0 || idx >= _mediaQueue.length) {
      return null;
    }
    return _mediaQueue[idx];
  }

  /// 推送播放状态/媒体项到 audio_service 通知栏（v1.2）。
  /// 队列仅在池变化后推送；位置/播放状态按事件高频推送。
  void _publishNotificationState() {
    final handler = MusicAudioHandler.instance;
    if (handler == null) return;
    if (!identical(handler, _boundHandler)) {
      _boundHandler = handler;
      _notificationQueueDirty = true;
    }
    if (_notificationQueueDirty) {
      _notificationQueueDirty = false;
      handler.queue.add(List<MediaItem>.unmodifiable(_mediaQueue));
    }
    //媒体项跟随当前池索引（通知栏标题/时长）；队列未变时也要更新
    final item = _currentMediaItem;
    if (handler.mediaItem.value?.id != item?.id) {
      handler.mediaItem.add(item);
    }
    handler.playbackState.add(_buildPlaybackState());
  }

  PlaybackState _buildPlaybackState() {
    final processing = _player.processingState;
    final playing = _player.playing;
    final idx = _player.currentIndex ?? 0;
    //v1.2 修复：队列首/尾也始终显示上一首/下一首（app 内按钮支持首尾循环，
    //通知栏不能因为池索引到头就消失）；无当前歌时隐藏
    final hasSong = _currentSong != null && _mediaQueue.isNotEmpty;
    final hasPrev = hasSong;
    final hasNext = hasSong;
    final controls = [
      if (hasPrev) MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      if (hasNext) MediaControl.skipToNext,
    ];
    return PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: [
        for (var i = 0; i < controls.length; i++)
          if (controls[i] != MediaControl.stop) i,
      ],
      processingState: switch (processing) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing &&
          processing != ProcessingState.completed &&
          processing != ProcessingState.idle,
      updatePosition: _position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _mediaQueue.isEmpty ? null : idx,
    );
  }

  /// 点击歌曲：同一首歌切播放/暂停；不同歌加载并播放（并定位到队列）
  /// 返回 true 表示成功；false 表示加载失败（UI 弹提示）
  ///
  /// 加固（v1.0 第四阶段）：
  /// - 退出恢复态：恢复后播放器**未加载任何音源**（`audioSource == null`），
  ///   直接 `play()` 无效 → 改走 [_loadAndPlay] 真正加载再播
  /// - 手动点击播放（含"暂停→播放"恢复）立即触发"手动点击"调权
  ///   （v1.0 第四阶段优化：原来只在"不同歌切换"后加，恢复播放不加）
  Future<bool> toggle(Song song) async {
    if (_currentSong?.audioFilePath != song.audioFilePath) {
      SleepTimerService.instance.cancelPendingByManualAction();
      //v1.2：顺序模式手动点非当前歌 → 以点击歌为首重排队列，
      //“下一首”任务紧随其后（用户确认）
      PlaylistService.instance.rebuildQueueStartingAt(song.audioFilePath);
    }
    if (_currentSong?.audioFilePath == song.audioFilePath) {
      if (_isPlaying) {
        await _player.pause();
        return true;
      }
      //未播放：播放它（退出恢复态无音源 → 重新加载）
      if (_player.audioSource == null) {
        await _loadAndPlay(song);
      } else {
        _startPlayer(_player);
      }
      //阶段4：手动点击播放调权（+配置值；默认 30）
      WeightService.instance.applyBehavior(song, WeightBehavior.manualClick);
      return true;
    }
    //定位队列位置（不同歌）
    PlaylistService.instance.moveTo(song.audioFilePath);
    final ok = await _loadAndPlay(song);
    if (ok) {
      //阶段4：手动点击播放调权（+配置值；自动连播/切歌不加）
      WeightService.instance.applyBehavior(song, WeightBehavior.manualClick);
    }
    return ok;
  }

  /// 按队列索引播放（队列页点击）：定位到指定任务并播放
  Future<bool> playAt(int index) async {
    final task = PlaylistService.instance.taskAt(index);
    if (task == null) return false;
    final song = _findSong(task.songFilePath);
    if (song == null) return false;
    PlaylistService.instance.moveToIndex(index);
    final ok = await _loadAndPlay(song);
    if (ok) {
      //阶段4：手动点击播放调权（队列页点歌同样算"手动点击"）
      WeightService.instance.applyBehavior(song, WeightBehavior.manualClick);
    }
    return ok;
  }

  /// 搜索页点击播放（阶段5）：定位队列并播放，触发"搜索播放"调权
  /// （+配置值）。**不叠加 manualClick**——搜索播放是独立行为，
  /// 避免一次点击双调权。
  Future<bool> playFromSearch(Song song) async {
    PlaylistService.instance.moveTo(song.audioFilePath);
    final ok = await _loadAndPlay(song);
    if (ok) {
      WeightService.instance.onSearchPlay(song);
    }
    return ok;
  }

  /// 加载并播放一首歌（所有切歌的公共底座）。**方案 A（v1.0 第四阶段）**：
  /// 不再单曲加载，而是**整池队列加载**（[ConcatenatingAudioSource]，池 =
  /// 当前播放源顺序的有效歌曲列表），通知栏/锁屏由此自动获得
  /// "上一首/下一首"按钮（just_audio_background 依据队列长度生成控件）。
  ///
  /// [fromAutoComplete]：true 表示由"播完自动连播"触发——
  /// 自动连播不算"快切"，不触发 10 秒快切扣权。
  ///
  /// 阶段4 接入：
  /// - 切走旧歌前检查"10 秒内快切"（仅用户主动切歌）
  /// - 播放成功记录开始时刻（供下一次快切判定）
  /// - 加权随机模式下播放成功触发播放衰减
  ///
  /// 时序约定（关键）：**先更新 `_currentSong`/`_pool` 再 `setAudioSource`**——
  /// 播放器就绪后发出的 `currentIndex=initialIndex` 事件会被
  /// [_onPlayerIndexChanged] 识别为"同歌"而忽略，避免被误判为通知切歌。
  Future<bool> _loadAndPlay(
    Song song, {
    bool fromAutoComplete = false,
    Duration? initialPosition,
  }) async {
    //① 切走旧歌前：检查是否"10 秒内快切"（主动切歌才扣权）
    if (!fromAutoComplete && _currentSong != null && _songStartTime != null) {
      final elapsed = DateTime.now().difference(_songStartTime!);
      if (elapsed.inSeconds <= 10) {
        WeightService.instance
            .applyBehavior(_currentSong!, WeightBehavior.quickSkip);
      }
    }
    //构建整池队列（含目标歌曲；单曲循环 = 单元素池，通知不显示上下首）
    //随机模式返回 (首尾双副本池, 真实歌索引)——真实歌在中间、前后恒有
    //元素，通知/锁屏双向恒有"上一首/下一首"（v1.0 第四阶段修复：
    //此前 indexWhere 命中首副本 index0 → 播放 index0 无"上一首"）
    final (pool, targetIndex) = _buildPoolWithTarget(song);
    try {
      await _player.stop();
      //播放器循环模式（v1.0 第四阶段）：
      //- 单曲循环 → LoopMode.one：播完自动重播当前歌；
      //  且 just_audio_background 在 repeatMode.one 下 getRelativeIndex(±1)
      //  返回当前索引 → 通知/锁屏**恒有"上一首/下一首"**，点击 = 重播当前歌
      //- 其余模式 → off：播完走 _onSongCompleted 分流，连播仍代码驱动
      await _player.setLoopMode(
        PlaylistService.instance.mode == PlayMode.repeatOne
            ? LoopMode.one
            : LoopMode.off,
      );
      //先同步池与当前歌，再加载（见时序约定注释）
      _pool = pool;
      _rebuildMediaQueue();
      _currentSong = song;
      _markNewPlaySession();
      _songStartTime = DateTime.now();
      //记录"当前播放器池是按哪个模式构建的"：onModeChanged 据此判断
      //顺序 ↔ 单曲循环能否走"只切 LoopMode、不重建"的快路径
      //（否则启动后第一次切换会误重建，产生不必要的换源间隙）
      _lastMode = PlaylistService.instance.mode;
      notifyListeners();
      //每个音源仍带 MediaItem 标签（v1.2 由 audio_service 通知栏使用）
      await _player.setAudioSource(
        _buildPoolSource(pool),
        initialIndex: targetIndex < 0 ? 0 : targetIndex,
      );
      //v1.2：新音源加载后恢复当前倍速
      await _player.setSpeed(_playbackSpeed);
      //模式切换等场景：重建后**先 seek 到原进度再播放**——
      //play() 之前 seek 才可靠（播放中 seek 可能因音源刚加载被重置），
      //保证"切模式不从头重播"（v1.0 第四阶段优化 1）
      if (initialPosition != null && initialPosition > Duration.zero) {
        try {
          await _player.seek(initialPosition);
        } catch (e) {
          debugPrint('[playback] 恢复进度失败（忽略）：$e');
        }
      }
      notifyListeners();
      //v1.0 第四阶段：持久化当前歌曲路径（退出重进后恢复显示；
      //失败不阻断播放，测试环境无平台通道时走这里）
      _persistCurrentSong(song);
      _startPlayer(_player);
      _publishNotificationState();
      //② 加权随机模式下：播放衰减（周期内第 1~4 次减超出部分的 20%）
      if (PlaylistService.instance.mode == PlayMode.weightedRandom) {
        WeightService.instance.applyPlayDecay(song);
      }
      return true;
    } catch (e) {
      //文件路径失效/权限不足等异常：不改 _currentSong，返回失败
      debugPrint('[playback] 加载失败：${song.audioFilePath} → $e');
      return false;
    }
  }

  /// 构建当前播放源对应的**整池媒体队列**（方案 A，v1.0 第四阶段）：
  /// - 池 = 播放队列 [PlaylistService.tasks] 中**有效**（能按路径找到歌）
  ///   的歌曲，保持任务顺序（顺序 = 源顺序；随机 = 采样批次）
  /// - **单曲循环也用完整池**（配合 LoopMode.one，通知恒有上下首且重播当前）
  /// - **随机模式（普通随机/加权随机）首尾填充当前歌副本**：
  ///   保证目标歌无论落在池首/池尾，通知/锁屏都恒有"上一首/下一首"按钮
  ///   （池首"上一首"→ 池尾副本（重播当前）；池尾"下一首"→ 池首副本）
  /// - 池为空（异常兜底）：退化为单曲
  /// 构建当前播放源的整池队列，并返回**目标歌曲在池中的索引**。
  ///
  /// - 顺序/单曲循环：池 = 任务有效歌曲（原顺序），目标索引 = 歌曲位置
  /// - 随机模式（普通随机/加权随机）：池 = `[song, ...完整池, song]`——
  ///   首尾各放一个当前歌副本，**真实歌保持在原位置**（出现 3 次）。
  ///   just_audio_background 在 LoopMode.off 下 index 0 的 previous 恒为
  ///   null（getRelativeIndex(-1)），所以目标歌必须位于中间（index ≥ 1）
  ///   才能让通知/锁屏**双向恒有"上一首/下一首"**；
  ///   点首/尾副本 = 重播当前歌（同歌分支刷新队列）。
  ///   目标索引 = 真实歌位置（origPos + 1）——不能用 indexWhere（会命中
  ///   首副本 index0，导致播放 index0 后通知栏没有"上一首"，此前 bug）。
  (List<Song>, int) _buildPoolWithTarget(Song song) {
    final mode = PlaylistService.instance.mode;
    final pool = <Song>[];
    final poolTaskIndices = <int>[];
    final tasks = PlaylistService.instance.tasks;
    for (var i = 0; i < tasks.length; i++) {
      final s = _findSong(tasks[i].songFilePath);
      if (s != null) {
        pool.add(s);
        poolTaskIndices.add(i);
      }
    }
    if (pool.isEmpty) {
      pool.add(song);
      poolTaskIndices.add(-1);
    }
    //v1.2 修复：队列存在重复歌曲任务时，不能按路径取第一个匹配——
    //否则播放第 5 个任务（路径与第 2 个相同）会定位回第 2 个，
    //app 内"下一首"在 2~4 之间循环。优先按当前任务索引定位。
    var target = poolTaskIndices.indexOf(PlaylistService.instance.currentIndex);
    if (target < 0) {
      target = pool.indexWhere((s) => s.audioFilePath == song.audioFilePath);
    }
    if (mode == PlayMode.realRandom || mode == PlayMode.weightedRandom) {
      if (target < 0) {
        pool.insert(0, song);
        target = 0;
      }
      return ([song, ...pool, song], target + 1);
    }
    return (pool, target < 0 ? 0 : target);
  }

  /// 把整池歌曲转成 just_audio 队列音源（每个 child 带 MediaItem 标签；
  /// id 加索引后缀，避免池内重复路径导致 id 冲突）
  ConcatenatingAudioSource _buildPoolSource(List<Song> pool) {
    return ConcatenatingAudioSource(
      children: [
        for (var i = 0; i < pool.length; i++)
          AudioSource.uri(
            Uri.file(pool[i].audioFilePath),
            tag: MediaItem(
              id: '${pool[i].audioFilePath}#$i',
              title: pool[i].name,
              artist: '',
              //带上时长，通知栏/锁屏可显示
              duration: Duration(milliseconds: pool[i].duration),
            ),
          ),
      ],
    );
  }

  /// 播放器队列索引变化（方案 A）：
  ///
  /// 代码驱动的切歌（[toggle]/[playAt]/[playFromSearch]/[playNext]/
  /// [playPrevious]）都会先设置 `_currentSong` 再 `setAudioSource`，所以
  /// 事件到达时索引对应歌 = 当前歌 → 直接忽略，**不重复调权**。
  ///
  /// 索引对应歌 ≠ 当前歌时，说明是**非代码驱动**的切歌：
  /// - 通知栏/锁屏点击"上一首/下一首"（播放器内部 seek）
  /// - 播放器播完一首后自动连播池内下一首（不再走 `_onSongCompleted`）
  /// 此时统一用"上一首实际播放时长"判定调权：
  /// - 播够整首（时长 - 2s 容差）→ 自然播完调权（对齐"自动连播"语义）
  /// - 10 秒内被切走 → 快切扣权（通知切歌 = 主动切歌）
  /// - 中间段（听了 30 秒手动切走）→ 不调权（对齐现状手动切歌语义）
  ///
  /// 同步播放队列游标（v1.0 第四阶段修复）：通知/自动连播切歌后，
  /// 把 [PlaylistService] 的任务游标移到对应任务（moveToIndex，不重建
  /// 随机批次）——队列页"当前歌高亮"与 app 内"下一首"位置随之正确
  /// （此前游标停在旧位置 → 通知切歌后高亮丢失、app 内下一首会重播
  /// "上次该播的歌"）。
  void _onPlayerIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _pool.length) return;
    final song = _pool[index];
    //睡眠定时到点后，若播放器原生自动连播抢先切到下一首：
    //立即消费 pending 并暂停，避免继续播放且倒计时卡在 0:00
    if (SleepTimerService.instance.pendingPause &&
        _currentSong?.audioFilePath != song.audioFilePath) {
      _sleepEndTimer?.cancel();
      _sleepEndTimer = null;
      if (SleepTimerService.instance.consumePendingPause()) {
        unawaited(pause());
      }
      return;
    }
    if (_currentSong?.audioFilePath == song.audioFilePath) {
      //同歌：不重播、不调权（当前歌没变）——但通知/池内切到同歌的
      //**另一个任务**（随机批次重复歌 / 顺序模式重复插入）时，游标要
      //跟随到正在播放的具体任务，否则队列页高亮停在旧任务。
      //（v1.0 第四阶段：单一权威队列 = 池只作快照、切歌只移游标、换歌
      //才重建，故这里仍不重建批次。）
      final loc = _locateTask(song.audioFilePath, index);
      if (loc >= 0 && loc != PlaylistService.instance.currentIndex) {
        PlaylistService.instance.moveToIndex(loc);
      }
      return;
    }
    final prev = _currentSong;
    final prevStart = _songStartTime;
    _currentSong = song;
    _markNewPlaySession();
    _songStartTime = DateTime.now();
    notifyListeners();
    _schedulePlayCount();
    //同步播放队列游标（**所有模式统一按路径定位、只移游标，不重建批次**）：
    //同歌（当前歌没变）也需要跟随：通知/池内切到**同歌不同副本**
    //（随机批次重复歌、顺序模式"添加下一首"重复插入）时游标应移到
    //正在播放的那个任务，否则高亮停在旧任务（v1.1-2 修复）。
    //播放器池是 tasks 的**快照**（构建时刻的顺序），通知/锁屏在池内前后
    //切歌 = 在 app 队列中前后移动 → 顺序一致、高亮正确；
    //app 队列的"顺序变化"（点歌 / 自动连播 / 添加下一首后 app 内下一首）
    //由 _loadAndPlay 重建池时同步——**不做双队列互相覆盖**，
    //消除"通知队列与 app 队列竞争"（v1.0 第四阶段，参照业界单一权威
    //队列做法；此前随机模式用 moveTo 重建批次，播放器池未同步 →
    //每切一次都重建、越切越脱节，还连带"添加下一首"错乱）
    //定位游标（**按"出现次数"对齐重复歌曲**，v1.1-2 统一封装）：
    //播放队列允许同一首歌出现多次（"添加下一首"可重复插入），而
    //indexWhere 只返回**第一个**匹配——系统切歌播到第二个 C 时游标会
    //错指第一个 C，导致第一个 C 的"下一首"标记被清、第二个 C/D 被
    //误判"未播放"。正确做法 = 统计 song 在池中（含当前 index）的出现
    //序号 N，在 tasks 中找**第 N 个**相同路径任务；**随机模式池含首尾
    //副本，按"池位置 index-1 = 任务位置"直接映射**（此前用 occurrence
    //会把首副本算进去 → 播放第 k 个副本时错移到第 k+1 个 → 高亮错位）
    final taskIdx = _locateTask(song.audioFilePath, index);
    if (taskIdx >= 0) {
      PlaylistService.instance.moveToIndex(taskIdx);
    }
    if (prev != null && prevStart != null) {
      final played = DateTime.now().difference(prevStart);
      final songDuration = Duration(milliseconds: prev.duration);
      if (played.inMilliseconds >= songDuration.inMilliseconds - 2000) {
        //自然播完：完整播完调权（+配置值）
        WeightService.instance
            .applyBehavior(prev, WeightBehavior.completedPlaying);
      } else if (played.inSeconds <= 10) {
        //10 秒内被切走：快切扣权
        WeightService.instance.applyBehavior(prev, WeightBehavior.quickSkip);
      }
    }
    //加权随机模式：播放衰减
    if (PlaylistService.instance.mode == PlayMode.weightedRandom) {
      WeightService.instance.applyPlayDecay(song);
    }
    _persistCurrentSong(song);
  }

  /// 池中位置 [poolIndex] → app 队列任务索引（-1 = 无对应任务）。
  ///
  /// - **随机模式**：池 = `[首副本, task0..taskN-1, 尾副本]` → 任务索引
  ///   = `poolIndex - 1`（首/尾副本 = 重播当前歌，返回 -1 不动游标；
  ///   目标歌不在批次时池补位歌同样无对应任务，返回 -1）
  /// - **顺序/单曲循环**：池 = tasks（无副本）→ 按"出现序号"匹配
  ///   （同一首歌可多次出现，"添加下一首"重复插入时需对齐到第 N 个）
  int _locateTask(String audioFilePath, int poolIndex) {
    final tasks = PlaylistService.instance.tasks;
    final mode = PlaylistService.instance.mode;
    final isRandom =
        mode == PlayMode.realRandom || mode == PlayMode.weightedRandom;
    if (isRandom) {
      final taskIdx = poolIndex - 1;
      if (taskIdx >= 0 &&
          taskIdx < tasks.length &&
          tasks[taskIdx].songFilePath == audioFilePath) {
        return taskIdx;
      }
      return -1;
    }
    var occurrence = 0;
    for (var i = 0; i <= poolIndex; i++) {
      if (_pool[i].audioFilePath == audioFilePath) occurrence++;
    }
    var seen = 0;
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].songFilePath == audioFilePath) {
        seen++;
        if (seen == occurrence) return i;
      }
    }
    return -1;
  }

  /// 播放模式切换（v1.2 双播放器无缝换源）。
  ///
  /// 池形状变化时**不改动正在出声的播放器**：让备用播放器静音加载新池、
  /// seek 到旧播放器当前进度并起播（音量 0），随后瞬时交换主备、静音并
  /// 暂停旧播放器——切换全程旧音频连续，真正没有静音间隙。
  ///
  /// 顺序 ↔ 单曲循环仍只切 LoopMode，不换池。
  /// 快速连续切换经 [_modeSwitchChain] 串行执行。
  Future<void> onModeChanged() {
    final next = _modeSwitchChain.then((_) => _applyModeChanged());
    //失败不断链：一次切换异常不影响后续切换，也不把异常抛给弹窗调用方
    final guarded = next.catchError((Object e) {
      debugPrint('[playback] 模式切换串行链异常（忽略）：$e');
    });
    _modeSwitchChain = guarded;
    return guarded;
  }

  Future<void> _applyModeChanged({bool force = false}) async {
    final song = _currentSong;
    if (song == null) return;
    final mode = PlaylistService.instance.mode;
    final prevMode = _lastMode;
    //同一模式重复点击（弹窗里再点当前模式）：无需任何重建，避免无谓换源
    if (!force && mode == prevMode && _player.audioSource != null) return;
    //① 顺序播放 ↔ 单曲循环：池形状相同，只切循环模式，不重建音源。
    //   额外要求"播放器池顺序与当前 tasks 顺序一致"——否则（如随机 →
    //   单曲循环 → 顺序）app 队列已按顺序重建、播放器仍是随机排列。
    final poolSameShape = !force &&
        _player.audioSource != null &&
        (mode == PlayMode.repeatOne || mode == PlayMode.sequence) &&
        (prevMode == PlayMode.repeatOne || prevMode == PlayMode.sequence) &&
        _poolMatchesTaskOrder();
    if (poolSameShape) {
      try {
        await _player.setLoopMode(
          mode == PlayMode.repeatOne ? LoopMode.one : LoopMode.off,
        );
      } catch (e) {
        debugPrint('[playback] 切换循环模式失败（忽略）：$e');
      }
      _lastMode = mode;
      _publishNotificationState();
      return;
    }
    //② 池形状变化：双播放器预加载后交换。
    final wasPlaying = _player.playing;
    final oldPlayer = _activePlayer;
    final standby = _standbyPlayer;
    final pos = wasPlaying ? _player.position : _position;
    //回滚用旧状态
    final oldPool = _pool;
    final oldMediaQueue = _mediaQueue;
    final oldSong = _currentSong;
    final oldStart = _songStartTime;
    final oldLastMode = _lastMode;
    final watch = Stopwatch()..start();
    var swapped = false;
    try {
      final (pool, targetIndex) = _buildPoolWithTarget(song);
      await standby.setLoopMode(
        mode == PlayMode.repeatOne ? LoopMode.one : LoopMode.off,
      );
      await standby.setVolume(0);
      await standby.setAudioSource(
        _buildPoolSource(pool),
        initialIndex: targetIndex < 0 ? 0 : targetIndex,
      );
      await standby.setSpeed(_playbackSpeed);
      //对齐进度：播放中旧播放器在加载期间继续前进，备用播放器 seek 到它
      //此刻的进度（含加载耗时）；暂停态旧播放器不动，直接用暂停位置。
      final aligned = wasPlaying ? pos + watch.elapsed : pos;
      if (aligned > Duration.zero) {
        await standby.seek(aligned);
      }
      if (wasPlaying) {
        _startPlayer(standby);
        //给原生层一点起播时间：交换时新播放器已在出声（音量 0）；
        //交换只静音旧播放器并开新音量，重叠仅 1~2ms，十几毫秒的位置
        //偏差听感上不可辨（且不会形成持续双声）
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      //交换主备（此后 UI/权重/通知只跟随新播放器）
      swapped = true;
      _activePlayer = standby;
      _standbyPlayer = oldPlayer;
      _pool = pool;
      _rebuildMediaQueue();
      _currentSong = song;
      _songStartTime = wasPlaying ? DateTime.now() : null;
      _bindPlayer(standby);
      notifyListeners();
      _publishNotificationState();
      final oldPosMs = oldPlayer.position.inMilliseconds;
      final newPosMs = standby.position.inMilliseconds;
      await standby.setVolume(1.0);
      if (wasPlaying) {
        //先静音旧播放器再暂停：两者内容对齐，几毫秒重叠不可闻
        unawaited(() async {
          try {
            await oldPlayer.setVolume(0);
            await oldPlayer.pause();
            await oldPlayer.setVolume(1.0);
          } catch (e) {
            debugPrint('[playback] 停旧播放器失败（忽略）：$e');
          }
        }());
      }
      _lastMode = mode;
      debugPrint('[playback] 双播放器切源完成：${prevMode?.name} → ${mode.name}'
          '（旧 ${oldPosMs}ms / 新 ${newPosMs}ms，新播放中=${standby.playing}，'
          '预加载 ${watch.elapsedMilliseconds}ms）');
    } catch (e) {
      debugPrint('[playback] 双播放器切源失败（回滚）：$song → $e');
      if (swapped) {
        //已交换后失败：切回旧播放器并恢复旧状态，避免静音
        _activePlayer = oldPlayer;
        _standbyPlayer = standby;
        _pool = oldPool;
        _mediaQueue = oldMediaQueue;
        _currentSong = oldSong;
        _songStartTime = oldStart;
        _lastMode = oldLastMode;
        _bindPlayer(oldPlayer);
        notifyListeners();
        try {
          await oldPlayer.setVolume(1.0);
          if (wasPlaying) _startPlayer(oldPlayer);
          await standby.pause();
          await standby.setVolume(1.0);
        } catch (_) {}
        _publishNotificationState();
      } else {
        try {
          await standby.stop();
          await standby.setVolume(1.0);
        } catch (_) {}
      }
    }
  }

  /// 播放器池顺序是否与 app 队列（tasks）有效歌曲顺序完全一致（v1.1-4）。
  /// 用于判断"顺序 ↔ 单曲循环"能否走只切 LoopMode 的快路径。
  bool _poolMatchesTaskOrder() {
    final expected = <String>[];
    for (final task in PlaylistService.instance.tasks) {
      if (_findSong(task.songFilePath) != null) {
        expected.add(task.songFilePath);
      }
    }
    if (expected.isEmpty || expected.length != _pool.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] != _pool[i].audioFilePath) return false;
    }
    return true;
  }

  /// 持久化当前歌曲路径（fire-and-forget；通知切歌也记录，供退出恢复用）
  Future<void> _persistCurrentSong(Song song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentSongPathKey, song.audioFilePath);
    } catch (e) {
      //测试环境无平台通道等：忽略
      debugPrint('[playback] 持久化当前歌曲失败（忽略）：$e');
    }
  }

  /// 暂停
  /// 设置倍速（0.1~5.0）；同时应用到主/备播放器，换源后保持
  Future<void> setPlaybackSpeed(double speed) async {
    final v = speed.clamp(0.1, 5.0).toDouble();
    _playbackSpeed = v;
    try {
      await _player.setSpeed(v);
      await _standbyPlayer.setSpeed(v);
    } catch (e) {
      debugPrint('[playback] 设置倍速失败：$e');
    }
    notifyListeners();
  }

  Future<void> pause() async {
    //到点后用户手动暂停：取消"播完再停"的待处理状态
    SleepTimerService.instance.cancelPendingByManualAction();    //暂停瞬间把精确位置写入缓存：暂停后 positionStream 停止发值，
    //供"暂停态切换模式"恢复进度使用
    if (_isPlaying) _position = _player.position;
    await _player.pause();
    _publishNotificationState();
  }

  /// 恢复播放（通知栏/锁屏播放键，v1.2）
  Future<void> resume() async {
    final song = _currentSong;
    if (song == null) return;
    if (_player.audioSource == null) {
      await _loadAndPlay(song);
      return;
    }
    _startPlayer(_player);
    _publishNotificationState();
  }

  /// 通知栏"下一首"：池内 seek（由 currentIndex 监听同步游标/权重），
  /// 避免走 [_loadAndPlay] 重建整池造成间隙。
  Future<void> skipToNextInPool() async {
    if (_currentSong == null) return;
    SleepTimerService.instance.cancelPendingByManualAction();
    if (PlaylistService.instance.mode == PlayMode.repeatOne) {
      await _player.seek(Duration.zero, index: _player.currentIndex);
      return;
    }
    final idx = _player.currentIndex ?? 0;
    if (idx + 1 < _pool.length) {
      await _player.seek(Duration.zero, index: idx + 1);
    } else {
      //v1.2 修复：池末尾的通知栏"下一首"按 app 内语义循环/追加下一首
      await playNext();
    }
  }

  /// 通知栏"上一首"：池内 seek（单曲循环 = 重播当前）
  Future<void> skipToPreviousInPool() async {
    if (_currentSong == null) return;
    SleepTimerService.instance.cancelPendingByManualAction();
    if (PlaylistService.instance.mode == PlayMode.repeatOne) {
      await _player.seek(Duration.zero, index: _player.currentIndex);
      return;
    }
    final idx = _player.currentIndex ?? 0;
    if (idx > 0) {
      await _player.seek(Duration.zero, index: idx - 1);
    } else {
      //v1.2 修复：池首的"上一首"按 app 内语义回到最后一首
      await playPrevious();
    }
  }

  /// 通知栏媒体队列点击：池内定位（不重建，不额外调权）
  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _pool.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  /// 停止播放（通知栏停止键）：释放播放并回到未播放态
  Future<void> stopPlayback() async {
    await _player.stop();
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
    _publishNotificationState();
  }

  /// 退出恢复（v1.0 第四阶段）：恢复上次播放的歌曲——
  /// **只恢复显示、保持暂停**（不自动出声），由 [LibraryProvider.loadSongs]
  /// 在歌曲库加载完成后调用。
  ///
  /// - 持久化的路径仍在当前库中 → 设为当前歌曲（时长取库数据，进度归零）
  /// - 文件已被删除/库中不存在 → 清除持久化记录（避免每次都空恢复）
  Future<void> restoreLastSongIfExists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_currentSongPathKey);
      if (path == null) return;
      final song = _findSong(path);
      if (song == null) {
        //歌曲已不在库中（文件夹变更/文件删除）：清除记录
        await prefs.remove(_currentSongPathKey);
        return;
      }
      _currentSong = song;
      _markNewPlaySession();
      _songStartTime = null; //未播放，不参与快切判定
      _position = Duration.zero;
      _duration = Duration(milliseconds: song.duration);
      notifyListeners();
    } catch (e) {
      //测试环境无平台通道等：忽略，不影响正常启动
      debugPrint('[playback] 恢复上次歌曲失败（忽略）：$e');
    }
  }

  /// 拖动进度
  Future<void> seek(Duration target) async {
    //先同步本地进度：暂停态下 positionStream 不再发值，
    //此时若切换模式需用最新拖动位置恢复（不能等事件回传）
    _position = target;
    notifyListeners();
    await _player.seek(target);
    _publishNotificationState();
  }

  /// "添加下一首"后的播放器池同步（v1.0 第四阶段修复）：
  /// [PlaylistService.addNextSong] 只在 app 队列插入任务，而播放器池是
  /// 构建时的**快照** → 用户紧接着用系统"下一首"切歌时，播放器在旧池里
  /// 步进，**新插入的歌曲被跳过（播放层面）**。此方法把新任务**同步插入
  /// 播放器池**（当前歌之后），使通知/锁屏与 app 队列一致。
  void onTaskInserted(int taskInsertAt, String songFilePath) {
    try {
      final src = _player.audioSource;
      if (src is! ConcatenatingAudioSource) return; //未加载（无池）
      final song = _findSong(songFilePath);
      if (song == null) return;
      //随机模式池含首尾副本（各 1 个当前歌副本）→ 任务位置在池中整体后移 1
      final mode = PlaylistService.instance.mode;
      final isRandom = mode == PlayMode.realRandom ||
          mode == PlayMode.weightedRandom;
      final insertPos = isRandom ? taskInsertAt + 1 : taskInsertAt;
      if (insertPos < 0 || insertPos > _pool.length) return;
      //id 唯一（同一首歌可多次插入；时间戳防冲突）
      final id = '$songFilePath#ins_${DateTime.now().microsecondsSinceEpoch}';
      src.insert(
        insertPos,
        AudioSource.uri(
          Uri.file(songFilePath),
          tag: MediaItem(
            id: id,
            title: song.name,
            artist: '',
            duration: Duration(milliseconds: song.duration),
          ),
        ),
      );
      _pool.insert(insertPos, song); //池同步（occurrence 计数随之正确）
      _rebuildMediaQueue();
      _publishNotificationState();
    } catch (e) {
      debugPrint('[playback] 同步插入播放器池失败（忽略）：$e');
    }
  }

  /// "移除队列任务"后的播放器池同步（v1.1-2 修复，对称 [onTaskInserted]）：
  /// [PlaylistService.removeTaskAt / removeTaskByPath] 只改 app 队列，
  /// 播放器池（通知栏/锁屏媒体队列）若不同步移除，系统"下一首"仍会
  /// seek 到已移除的歌并播放。此方法把同位置任务**同步移除出池**。
  void onTaskRemoved(int taskRemoveAt, String songFilePath) {
    try {
      final src = _player.audioSource;
      if (src is! ConcatenatingAudioSource) return; //未加载（无池）
      //随机模式池含首尾副本（各 1 个当前歌副本）→ 任务位置在池中整体后移 1
      final mode = PlaylistService.instance.mode;
      final isRandom = mode == PlayMode.realRandom ||
          mode == PlayMode.weightedRandom;
      final removePos = isRandom ? taskRemoveAt + 1 : taskRemoveAt;
      if (removePos < 0 || removePos >= _pool.length) return;
      //先同步内存池（occurrence/索引计数正确），再异步移除底层序列；
      //just_audio 的 removeAt 异步完成，失败仅打印（下次重建池自愈）
      _pool.removeAt(removePos);
      _rebuildMediaQueue();
      _publishNotificationState();
      unawaited(src.removeAt(removePos).catchError((Object e) {
        debugPrint('[playback] 同步移除播放器池失败（忽略）：$e');
      }));
    } catch (e) {
      debugPrint('[playback] 同步移除播放器池异常（忽略）：$e');
    }
  }

  /// 下一首：走播放队列；文件失效的任务自动跳过。
  /// **单曲循环模式下，手动"下一首"重播当前歌**（符合单曲循环本意）
  ///
  /// [fromAutoComplete]：true = 播完自动连播触发（不算"快切"）
  ///
  /// 加固（v1.0 第三阶段修复）：① 自身歌曲库未同步时回退到播放队列服务
  /// 的最新库找歌（避免"歌单源播完即停"）；② 单首加载失败（文件损坏/移动
  /// 等）继续尝试队列里的下一首，不再一失败就中断连播。
  Future<bool> playNext({bool fromAutoComplete = false}) async {
    if (!fromAutoComplete) {
      SleepTimerService.instance.cancelPendingByManualAction();
    }
    _syncLibraryFallback();
    if (_library.isEmpty) return false;
    if (PlaylistService.instance.mode == PlayMode.repeatOne) {
      return _replayCurrent();
    }
    //循环上限 = 库歌曲数 + 队列任务数：保证队列里每个失效任务
    //都被试过且库中每首歌都能被轮到（大量失效"下一首"任务时也不会提前退出）
    final maxSkips = _library.length + PlaylistService.instance.length;
    for (var i = 0; i < maxSkips; i++) {
      final task = PlaylistService.instance.nextTask();
      if (task == null) return false;
      final song = _findSong(task.songFilePath);
      if (song == null) continue;
      final ok = await _loadAndPlay(song, fromAutoComplete: fromAutoComplete);
      if (ok) return true;
      //加载失败：继续尝试下一首（跳过失效文件），避免连播中断
    }
    return false;
  }

  /// 上一首：走播放队列；文件失效的任务自动跳过。
  /// **单曲循环模式下，手动"上一首"同样重播当前歌**
  Future<bool> playPrevious() async {
    _syncLibraryFallback();
    if (_library.isEmpty) return false;
    if (PlaylistService.instance.mode == PlayMode.repeatOne) {
      return _replayCurrent();
    }
    //循环上限 = 库歌曲数 + 队列任务数（同上：失效任务多时也能全部跳过）
    final maxSkips = _library.length + PlaylistService.instance.length;
    for (var i = 0; i < maxSkips; i++) {
      final task = PlaylistService.instance.previousTask();
      if (task == null) return false;
      final song = _findSong(task.songFilePath);
      if (song == null) continue;
      final ok = await _loadAndPlay(song);
      if (ok) return true;
      //加载失败：继续尝试上一首
    }
    return false;
  }

  /// 自身歌曲库为空（如播放服务先于库加载被调用）时，
  /// 回退同步播放队列服务的最新库，保证找歌/连播不因时序中断。
  void _syncLibraryFallback() {
    if (_library.isEmpty) {
      _library = PlaylistService.instance.librarySnapshot;
    }
  }

  /// 播放完成：按模式分流
  /// - 单曲循环：重播当前歌（回到 0 继续播；重播调权在 _replayCurrent 内）
  /// - 其余：**先触发"完整播完"调权**（v1.0 第二阶段新增事件），再自动下一首
  ///   （fromAutoComplete=true：自动连播不算"快切"）
  ///
  /// 加固（v1.0 第三阶段修复）：整体 try/catch——调权或连播的任何异常
  /// 都只记录日志，绝不静默中断"播完自动连播"（此前异常会让播放停在
  /// 完成态，表现为"播放完就暂停"）。
  Future<void> _onSongCompleted() async {
    try {
      //v1.2 睡眠定时"播完当前歌曲再暂停"：到点后自然播完 → 暂停且不连播
      if (SleepTimerService.instance.consumePendingPause()) {
        await pause();
        return;
      }
      if (PlaylistService.instance.mode == PlayMode.repeatOne) {
        await _replayCurrent();
        return;
      }
      //自然播完（非快切、非单曲循环重播）：完整播完调权 +配置值
      if (_currentSong != null) {
        WeightService.instance
            .applyBehavior(_currentSong!, WeightBehavior.completedPlaying);
      }
      final ok = await playNext(fromAutoComplete: true);
      if (!ok) {
        debugPrint('[playback] 自动连播结束：队列已空或无可用歌曲');
      }
    } catch (e) {
      //任何异常都不阻断连播意图（下次完成事件仍会尝试）
      debugPrint('[playback] 自动连播异常：$e');
    }
  }

  /// 重播当前歌（单曲循环的"上一首/下一首/播完"共用）：
  /// just_audio 中 completed 状态下直接 play() 无效，必须先 seek 回 0
  Future<bool> _replayCurrent() async {
    if (_currentSong == null) return false;
    try {
      await _player.seek(Duration.zero);
      //极端场景（超短音源瞬间再次 completed）二次确认离开完成态
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      _startPlayer(_player);
      //显式同步播放状态：seek 重播期间 playingStream 可能不再发新值，
      //避免 UI 图标停在"暂停"（播放完成瞬间 _isPlaying 被置 false）
      _isPlaying = true;
      _markNewPlaySession();
      _schedulePlayCount();
      notifyListeners();
      //阶段4：单曲循环重播调权（+配置值）
      WeightService.instance
          .applyBehavior(_currentSong!, WeightBehavior.repeatOne);
      return true;
    } catch (e) {
      debugPrint('[playback] 重播当前歌失败：$e');
      return false;
    }
  }

  /// 按路径从库中找歌（找不到返回 null）
  Song? _findSong(String filePath) {
    for (final s in _library) {
      if (s.audioFilePath == filePath) return s;
    }
    return null;
  }

  @override
  void dispose() {
    for (final sub in _playerSubs) {
      unawaited(sub.cancel());
    }
    _playerSubs.clear();
    final interruptionSub = _interruptionSub;
    if (interruptionSub != null) unawaited(interruptionSub.cancel());
    final noisySub = _noisySub;
    if (noisySub != null) unawaited(noisySub.cancel());
    _playCountTimer?.cancel();
    _sleepEndTimer?.cancel();
    SleepTimerService.instance.removeListener(_onSleepTimerChanged);
    unawaited(_playerA.dispose());
    unawaited(_playerB.dispose());
    super.dispose();
  }
}

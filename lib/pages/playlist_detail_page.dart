import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_icon_colors.dart';
import '../models/list_sort_mode.dart';
import '../models/play_mode.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../models/status_colors.dart';
import '../models/weight_behavior.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/list_view_prefs_service.dart';
import '../services/playback_stats_service.dart';
import '../services/playlist_service.dart';
import '../services/song_sorter.dart';
import '../services/weight_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_notice.dart';
import '../widgets/bottom_playback_bar_widget.dart';
import '../widgets/left_drawer_widget.dart';
import '../widgets/list_info_bar.dart';
import '../widgets/locate_current_button.dart';
import '../widgets/play_mode_sheet.dart';
import '../widgets/selection_action_bar.dart';
import '../widgets/song_long_press_menu.dart';
import '../widgets/song_selection_controller.dart';
import '../widgets/song_sort_sheet.dart';
import 'about_page.dart';
import 'favorites_page.dart';
import 'home_play_tasks_page.dart';
import 'settings_page.dart';

/// 歌单详情页（v1.0 第三阶段）
///
/// 展示某用户自定义歌单内的歌曲（顺序 = 歌单内添加顺序）：
/// - 点击歌曲播放：先切播放源为**该歌单**（队列 = 歌单内歌曲），再播放
/// - 长按歌曲 → 统一长按菜单（含"移除歌单"——仅本页显示）
/// - 行尾：星标（收藏开关）+ 添加下一首（与其他页一致）
/// - 按规划：**不做**批量加歌/移歌按钮、**不做**"重命名歌单"按钮
///   （重命名入口在抽屉内长按歌单，2026-10-26 用户确认）
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  /// 歌单 id（从 PlaylistProvider 动态取最新数据）
  final String playlistId;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  /// 歌曲列表滚动控制器（v1.0 第四阶段："定位当前播放歌曲"悬浮按钮）
  final ScrollController _listController = ScrollController();

  /// v1.2：歌单页独立排序（默认歌单顺序）
  ListSortMode _sortMode = ListSortMode.sourceOrder;

  /// v1.2 多选状态
  final SongSelectionController _selection = SongSelectionController();

  String get _listKey => ListViewPrefsService.keyForPlaylist(widget.playlistId);

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    _sortMode = ListViewPrefsService.instance.sortFor(_listKey);
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _toggleSelectionMode() {
    if (_selection.isSelecting) {
      _selection.exit();
    } else {
      _selection.enter();
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final playlistProvider = context.read<PlaylistProvider>();
    final library = context.read<LibraryProvider>();
    final playlist = playlistProvider.playlistById(widget.playlistId);
    if (playlist == null) return;
    final songs = List<Song>.of(_displaySongs(playlist, library));
    if (oldIndex < 0 || oldIndex >= songs.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = songs.removeAt(oldIndex);
    songs.insert(newIndex, moved);
    await ListViewPrefsService.instance
        .setCustomOrder(_listKey, songs.map((s) => s.audioFilePath).toList());
    if (!mounted) return;
    setState(() => _sortMode = ListSortMode.custom);
    if (PlaylistService.instance.source == PlaySource.playlist &&
        PlaylistService.instance.sourcePlaylistId == widget.playlistId &&
        PlaylistService.instance.mode == PlayMode.sequence) {
      PlaylistService.instance.applyListOrder(
        songs.map((s) => s.audioFilePath).toList(),
        keepSongId: AudioPlaybackService.instance.currentSongId,
      );
    }
  }

  Future<void> _showSortSheet() async {
    final selected = await showListSortSheet(
      context,
      current: _sortMode,
      options: const [
        ListSortMode.sourceOrder,
        ListSortMode.addTimeDesc,
        ListSortMode.addTimeAsc,
        ListSortMode.nameAsc,
        ListSortMode.nameDesc,
        ListSortMode.durationAsc,
        ListSortMode.durationDesc,
        ListSortMode.playCountAsc,
        ListSortMode.playCountDesc,
      ],
    );
    if (selected == null || !mounted) return;
    await ListViewPrefsService.instance.setSort(_listKey, selected);
    if (!mounted) return;
    setState(() => _sortMode = selected);
    if (PlaylistService.instance.source == PlaySource.playlist &&
        PlaylistService.instance.sourcePlaylistId == widget.playlistId &&
        PlaylistService.instance.mode == PlayMode.sequence) {
      final playlistProvider = context.read<PlaylistProvider>();
      final library = context.read<LibraryProvider>();
      final playlist = playlistProvider.playlistById(widget.playlistId);
      if (playlist != null) {
        final display = _displaySongs(playlist, library);
        PlaylistService.instance.applyListOrder(
          display.map((s) => s.audioFilePath).toList(),
          keepSongId: AudioPlaybackService.instance.currentSongId,
        );
      }
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// 点击歌单内歌曲：切播放源为该歌单，再交给播放服务播放
  Future<void> _onSongTap(Song song) async {
    final player = context.read<AudioPlaybackService>();
    //先切播放源（队列重建为歌单内歌曲；相同源重复进入不重建）
    await context
        .read<PlaylistService>()
        .setPlaySource(PlaySource.playlist, playlistId: widget.playlistId);
    if (!mounted) return;
    final ok = await player.toggle(song);
    if (!mounted) return;
    if (!ok) {
      _showSnackBar('播放失败，文件可能已被移动或删除');
    }
  }

  /// 抽屉（v1.0 第四阶段）：右滑打开。功能入口 = 导航型跳转；
  /// "选择音乐文件夹/主题色"依赖主页流程 → 提示回主页操作。
  Widget _buildDrawer(BuildContext context) {
    return LeftDrawerWidget(
      onScanFolder: () => _showDrawerHint(context, '请返回主页后，通过左上角菜单选择音乐文件夹'),
      onThemeTap: () => _showDrawerHint(context, '请返回主页后，通过左上角菜单设置主题色'),
      onFavoritesTap: () => _pushPage(context, const FavoritesPage()),
      onSettingsTap: () => _pushPage(context, const SettingsPage()),
      onAboutTap: () => _pushPage(context, const AboutPage()),
      //歌单详情页内点歌单：直接进入该歌单详情页
      onPlaylistTap: (p) => _pushPage(context, PlaylistDetailPage(playlistId: p.id)),
    );
  }

  /// 抽屉入口提示（root Overlay 浮层，随主题配色）
  void _showDrawerHint(BuildContext context, String message) {
    showAppNotice(context, message, duration: const Duration(seconds: 3));
  }

  void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: RouteSettings(name: _routeNameOf(page)),
      builder: (_) => page,
    ));
  }

  /// 目标页路由名（供"默认停留页面"记录；非目标页返回 null 不记录）
  String? _routeNameOf(Widget page) {
    if (page is FavoritesPage) return 'favorites';
    if (page is PlaylistDetailPage) return 'playlist:${page.playlistId}';
    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 批量加入歌单（v1.0 第四阶段）：
  /// 打开全库勾选页 → 用户勾选多首 → 批量加入当前歌单 → 提示加入数量
  Future<void> _openBatchAdd(String playlistId) async {
    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _BatchAddSongsPage(playlistId: playlistId),
      ),
    );
    if (selected == null || selected.isEmpty) return;
    if (!mounted) return;
    final added = context
        .read<PlaylistProvider>()
        .addSongsToPlaylist(playlistId, selected);
    if (!mounted) return;
    _showSnackBar(added > 0 ? '已加入 $added 首歌曲' : '所选歌曲都已在歌单中');
  }

  /// 歌单内歌曲：先按歌单路径顺序，再应用本页排序（v1.2）
  List<Song> _displaySongs(Playlist playlist, LibraryProvider library) {
    final byPath = {for (final s in library.songs) s.audioFilePath: s};
    final raw = <Song>[
      for (final p in playlist.songFilePaths)
        if (byPath[p] != null) byPath[p]!,
    ];
    return SongSorter.sort(
      raw,
      _sortMode,
      customOrder: ListViewPrefsService.instance.customOrderFor(_listKey),
      playCountOf: PlaybackStatsService.instance.countOf,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistProvider = context.watch<PlaylistProvider>();
    final playlist = playlistProvider.playlistById(widget.playlistId);
    if (playlist == null) {
      //歌单已被删除（如抽屉里长按删除后，详情页还在导航栈中）
      return Scaffold(
        appBar: AppBar(title: const Text('歌单')),
        body: const Center(child: Text('歌单不存在或已被删除')),
      );
    }
    final library = context.watch<LibraryProvider>();
    final mode = context.select((PlaylistService p) => p.mode);
    final songs = _displaySongs(playlist, library);
    final byPath = {for (final s in library.songs) s.audioFilePath: s};
    final selectedSongs = <Song>[
      for (final p in _selection.selectedPaths)
        if (byPath[p] != null) byPath[p]!,
    ];

    return Stack(
      children: [
        //页面级背景（补充 17 规范）：背景 + 遮罩在 Scaffold 之下
        AppBackground(playlistId: widget.playlistId),
        Scaffold(
          //v1.0 第四阶段：右滑打开抽屉（与主页一致：左边缘 60% 屏宽触发区域）
          drawerEdgeDragWidth: MediaQuery.sizeOf(context).width * 0.6,
          drawer: _buildDrawer(context),
          appBar: AppBar(
            //显式返回按钮：有 drawer 时避免 AppBar 自动变成"开抽屉"菜单按钮
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(playlist.name),
            centerTitle: true,
            //v1.0 第四阶段："批量加入歌单"入口
            actions: [
              IconButton(
                tooltip: '批量加入歌单',
                icon: const Icon(Icons.playlist_add_check),
                onPressed: () => _openBatchAdd(playlist.id),
              ),
            ],
            bottom: ListInfoBar(
              mode: mode,
              songCount: songs.length,
              sortLabel: _sortMode == ListSortMode.sourceOrder
                  ? '歌单顺序'
                  : _sortMode.label,
              onModeTap: () => showPlayModeSheet(context),
              onSortTap: _showSortSheet,
              onMultiTap: _toggleSelectionMode,
              multiActive: _selection.isSelecting,
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: songs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.queue_music,
                              size: 72,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            const Text('这个歌单还没有歌曲',
                                style: TextStyle(fontSize: 18)),
                            const SizedBox(height: 8),
                            Text(
                              '在歌曲上长按选择"加入歌单…"即可添加',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : (_selection.isSelecting
                        ? ReorderableListView.builder(
                            buildDefaultDragHandles: true,
                            onReorderStart: (_) =>
                                HapticFeedback.mediumImpact(),
                            onReorder: _onReorder,
                            itemCount: songs.length,
                            itemBuilder: (context, index) => KeyedSubtree(
                              key: ValueKey(songs[index].audioFilePath),
                              child: _buildSongTile(songs[index], index),
                            ),
                          )
                        : Stack(
                            children: [
                              ListView.builder(
                                controller: _listController,
                                itemCount: songs.length,
                                itemBuilder: (context, index) =>
                                    _buildSongTile(songs[index], index),
                              ),
                              _buildLocateButton(songs),
                            ],
                          )),
              ),
              if (_selection.isSelecting && selectedSongs.isNotEmpty)
                SelectionActionBar(
                  songs: selectedSongs,
                  onFinished: _selection.exit,
                ),
            ],
          ),
          //复用底部播放栏（全局播放状态）；播放队列图标 → 播放队列页
          bottomNavigationBar: BottomPlaybackBarWidget(
            onPlayTasksTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HomePlayTasksPage()),
            ),
          ),
        ),
      ],
    );
  }

  /// "定位"悬浮按钮：把正在播放的歌（高亮歌曲）滚动到屏幕中部偏上
  /// （约黄金分割 38.2% 处）。仅当当前歌在本歌单中时显示。
  Widget _buildLocateButton(List<Song> songs) {
    return LocateCurrentButton(
      songs: songs,
      heroTag: 'locate_current_playlist_${widget.playlistId}',
      onScrollTo: _scrollToCurrentSong,
    );
  }

  /// 滚动定位：目标行中心滚动到视口 38.2%（中部偏上 ≈ 黄金分割点）
  void _scrollToCurrentSong(int index) {
    const rowHeight = 72.0; //歌曲行高（ListTile 含 subtitle）
    final viewport = _listController.position.viewportDimension;
    final target = (index * rowHeight + rowHeight / 2) - viewport * 0.382;
    final maxExtent = _listController.position.maxScrollExtent;
    final offset = target.clamp(0.0, maxExtent > 0 ? maxExtent : 0.0);
    _listController.animateTo(
      offset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// 歌单内歌曲行：编号 + 音符 + 歌名 + 时长 + 星标 + 添加下一首；
  /// 当前播放的歌整行高亮（状态色-当前歌高亮，与其他页统一）
  Widget _buildSongTile(Song song, int index) {
    final highlightColor = StatusColors.of(context).currentHighlight;
    return Selector<AudioPlaybackService, String?>(
      selector: (_, p) => p.currentSongId,
      builder: (context, currentId, _) {
        final isCurrent = currentId == song.audioFilePath;
        if (_selection.isSelecting) {
          final order = _selection.orderOf(song.audioFilePath);
          final selected = order > 0;
          return ListTile(
            leading: Checkbox(
              value: selected,
              onChanged: (_) => _selection.toggle(song.audioFilePath),
            ),
            title: Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: selected ? FontWeight.bold : null,
              ),
            ),
            subtitle: Text(selected
                ? '已选第 $order 首'
                : _formatDuration(song.duration)),
            onTap: () => _selection.toggle(song.audioFilePath),
          );
        }
        return ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  color: isCurrent
                      ? highlightColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.music_note, color: isCurrent ? highlightColor : null),
            ],
          ),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? highlightColor : null,
              fontWeight: isCurrent ? FontWeight.bold : null,
            ),
          ),
          subtitle: Text(
            _formatDuration(song.duration),
            style: TextStyle(color: isCurrent ? highlightColor : null),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              //收藏开关（星标色可自定义，默认 amber；当前歌未收藏星标用高亮色）
              IconButton(
                iconSize: 22,
                tooltip: song.isFavorite ? '取消收藏' : '收藏',
                icon: Icon(
                  song.isFavorite ? Icons.star : Icons.star_border,
                  color: song.isFavorite
                      ? StatusColors.of(context).favoriteStar
                      : (isCurrent ? highlightColor : null),
                ),
                onPressed: () =>
                    context.read<LibraryProvider>().toggleFavorite(song),
              ),
              IconButton(
                iconSize: 22,
                tooltip: '添加到下一首',
                //当前播放的歌：添加图标用高亮色；其余用可自定义的添加图标色
                icon: Icon(
                  Icons.playlist_add,
                  color: isCurrent
                      ? highlightColor
                      : AppIconColors.of(context).add,
                ),
                onPressed: () =>
                    _onAddNext(song),
              ),
            ],
          ),
          onTap: () => _onSongTap(song),
          //长按 → 统一菜单（详情页显示"移除歌单"）
          onLongPress: () => showSongLongPressMenu(
            context,
            song,
            inPlaylistDetail: true,
            playlistId: widget.playlistId,
          ),
        );
      },
    );
  }

  /// "添加下一首"：插入当前播放的下一首 + 调权
  void _onAddNext(Song song) {
    context.read<PlaylistService>().addNextSong(song.audioFilePath);
    //"添加下一首"行为调权（+配置值）
    WeightService.instance.applyBehavior(song, WeightBehavior.addNext);
    _showSnackBar('已添加到下一首：${song.name}');
  }

  /// 毫秒 → m:ss
  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 批量加入歌单 - 全库勾选页（v1.0 第四阶段）
///
/// 展示歌曲库全部歌曲，复选框勾选（已在当前歌单中的歌曲标"已加入"并禁用）；
/// 底部"加入歌单（N）"按钮 → 返回勾选的路径列表（取消返回 null）。
/// 复用 AppBackground（与其余页面一致的背景/遮罩规范）。
class _BatchAddSongsPage extends StatefulWidget {
  const _BatchAddSongsPage({required this.playlistId});

  final String playlistId;

  @override
  State<_BatchAddSongsPage> createState() => _BatchAddSongsPageState();
}

class _BatchAddSongsPageState extends State<_BatchAddSongsPage> {
  final Set<String> _checked = {}; //勾选的歌曲路径

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playlistProvider = context.watch<PlaylistProvider>();
    final playlist = playlistProvider.playlistById(widget.playlistId);
    final inPlaylist = playlist == null
        ? <String>{}
        : {...playlist.songFilePaths}; //已在此歌单的路径
    final songs = library.songs;
    final count = _checked.length;

    return Stack(
      children: [
        AppBackground(playlistId: widget.playlistId),
        Scaffold(
          appBar: AppBar(title: const Text('批量加入歌单'), centerTitle: true),
          body: songs.isEmpty
              ? const Center(child: Text('歌曲库为空'))
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final alreadyIn = inPlaylist.contains(song.audioFilePath);
                    final checked = _checked.contains(song.audioFilePath);
                    return CheckboxListTile(
                      value: checked,
                      //已在歌单中：禁用（不允许重复加入）
                      onChanged: alreadyIn
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _checked.add(song.audioFilePath);
                                } else {
                                  _checked.remove(song.audioFilePath);
                                }
                              }),
                      title: Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: alreadyIn
                          ? const Text('已在歌单中')
                          : Text(_formatDuration(song.duration)),
                      secondary: alreadyIn
                          ? const Icon(Icons.check_circle)
                          : const Icon(Icons.music_note),
                    );
                  },
                ),
          //底部确认按钮：数量随勾选实时变化
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: count == 0
                    ? null
                    : () => Navigator.of(context).pop(_checked.toList()),
                child: Text(count == 0 ? '请选择歌曲' : '加入歌单（$count）'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 毫秒 → m:ss（与详情页一致）
  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

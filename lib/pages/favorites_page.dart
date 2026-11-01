import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/list_sort_mode.dart';
import '../models/play_mode.dart';
import '../models/theme_palette.dart';
import '../models/app_icon_colors.dart';
import '../models/song.dart';
import '../models/status_colors.dart';
import '../models/weight_behavior.dart';
import '../providers/library_provider.dart';
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
import 'home_play_tasks_page.dart';
import 'playlist_detail_page.dart';
import 'settings_page.dart';

/// 收藏页（阶段5）：只显示已收藏（isFavorite）的歌曲。
///
/// 行尾：星形按钮（取消收藏）+ 添加下一首；点击播放走手动点击调权。
/// 空状态引导用户去主页收藏歌曲。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  /// 歌曲列表滚动控制器（v1.0 第四阶段："定位当前播放歌曲"悬浮按钮）
  final ScrollController _listController = ScrollController();

  /// v1.2 多选状态
  final SongSelectionController _selection = SongSelectionController();

  /// v1.2：收藏页独立排序（默认收藏顺序）
  ListSortMode _sortMode = ListSortMode.sourceOrder;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    _sortMode = ListViewPrefsService.instance.sortFor(
      ListViewPrefsService.keyFavorites,
    );
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

  /// 拖拽保存收藏页自定义顺序
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final library = context.read<LibraryProvider>();
    final songs = List<Song>.of(_displayFavorites(library));
    if (oldIndex < 0 || oldIndex >= songs.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = songs.removeAt(oldIndex);
    songs.insert(newIndex, moved);
    await ListViewPrefsService.instance
        .setCustomOrder(_listKey, songs.map((s) => s.audioFilePath).toList());
    if (!mounted) return;
    setState(() => _sortMode = ListSortMode.custom);
    if (PlaylistService.instance.source == PlaySource.favorites &&
        PlaylistService.instance.mode == PlayMode.sequence) {
      PlaylistService.instance.applyListOrder(
        songs.map((s) => s.audioFilePath).toList(),
        keepSongId: AudioPlaybackService.instance.currentSongId,
      );
    }
  }

  String get _listKey => ListViewPrefsService.keyFavorites;

  /// 排序方式弹窗：只排当前列表；顺序播放且当前源是收藏时同步队列
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
    if (PlaylistService.instance.source == PlaySource.favorites &&
        PlaylistService.instance.mode == PlayMode.sequence) {
      final library = context.read<LibraryProvider>();
      final display = _displayFavorites(library);
      PlaylistService.instance.applyListOrder(
        display.map((s) => s.audioFilePath).toList(),
        keepSongId: AudioPlaybackService.instance.currentSongId,
      );
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// 点击歌曲：先切播放源为"我的收藏"（收藏虚拟歌单），再交给播放服务
  /// （同歌切播放/暂停，不同歌加载播放）
  Future<void> _onSongTap(BuildContext context, Song song) async {
    await context
        .read<PlaylistService>()
        .setPlaySource(PlaySource.favorites);
    if (!context.mounted) return;
    final player = context.read<AudioPlaybackService>();
    final ok = await player.toggle(song);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('播放失败，文件可能已被移动或删除')),
        );
    }
  }

  /// 收藏/取消收藏
  Future<void> _toggleFavorite(BuildContext context, Song song) async {
    await context.read<LibraryProvider>().toggleFavorite(song);
  }

  /// 抽屉（v1.0 第四阶段）：右滑打开。功能入口 = 导航型跳转；
  /// "选择音乐文件夹/主题色"依赖主页流程 → 提示回主页操作。
  Widget _buildDrawer(BuildContext context) {
    return LeftDrawerWidget(
      onScanFolder: () => _showDrawerHint(context, '请返回主页后，通过左上角菜单选择音乐文件夹'),
      onThemeTap: () => _showDrawerHint(context, '请返回主页后，通过左上角菜单设置主题色'),
      onFavoritesTap: () {}, //已在收藏页：关抽屉即可
      onSettingsTap: () => _pushPage(context, const SettingsPage()),
      onAboutTap: () => _pushPage(context, const AboutPage()),
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

  /// "添加下一首"：插入当前播放的下一首
  void _onAddNext(BuildContext context, Song song) {
    final playlist = context.read<PlaylistService>();
    playlist.addNextSong(song.audioFilePath);
    //阶段4："添加下一首"行为调权
    WeightService.instance.applyBehavior(song, WeightBehavior.addNext);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已添加到下一首：${song.name}')));
  }

  /// 收藏原始顺序（favorites.json 顺序；缺失歌曲用占位行顶住）
  List<Song> _rawFavorites(LibraryProvider library) {
    final favPaths = library.favoritePaths;
    final byPath = {for (final s in library.songs) s.audioFilePath: s};
    return <Song>[
      for (var i = 0; i < favPaths.length; i++)
        byPath[favPaths[i]] ??
            Song(
              name: _fileNameOf(favPaths[i]),
              audioFilePath: favPaths[i],
              addTime: '',
              sortNumber: i + 1,
            ),
    ];
  }

  /// 收藏页展示顺序（v1.2 独立排序）
  List<Song> _displayFavorites(LibraryProvider library) {
    return SongSorter.sort(
      _rawFavorites(library),
      _sortMode,
      customOrder:
          ListViewPrefsService.instance.customOrderFor(_listKey),
      playCountOf: PlaybackStatsService.instance.countOf,
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final mode = context.select((PlaylistService p) => p.mode);
    //v1.1：收藏列表基于**独立收藏集**构建（favorites.json 权威）——
    //歌曲库暂时缺失/正在扫描时用"占位行"（仅文件名）顶住，收藏不丢；
    //库恢复后自动显示完整信息（时长/编号等）。
    final favorites = _displayFavorites(library);
    final byPath = {for (final s in library.songs) s.audioFilePath: s};
    final selectedSongs = <Song>[
      for (final p in _selection.selectedPaths)
        if (byPath[p] != null) byPath[p]!,
    ];

    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeyFavorites),
        Scaffold(
      //v1.0 第四阶段：右滑打开抽屉（与主页一致：左边缘 60% 屏宽触发区域）
      drawerEdgeDragWidth: MediaQuery.sizeOf(context).width * 0.6,
      drawer: _buildDrawer(context),
      appBar: AppBar(
        //显式返回按钮：有 drawer 时避免 AppBar 自动变成"开抽屉"菜单按钮
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回主页',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('我的收藏'),
        centerTitle: true,
        bottom: ListInfoBar(
          mode: mode,
          songCount: favorites.length,
          sortLabel: _sortMode == ListSortMode.sourceOrder
              ? '收藏顺序'
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
            child: favorites.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_border,
                            size: 72,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        const Text('还没有收藏歌曲',
                            style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(
                          '在主页歌曲行尾点击星形按钮即可收藏',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
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
                        itemCount: favorites.length,
                        itemBuilder: (context, i) => KeyedSubtree(
                          key: ValueKey(favorites[i].audioFilePath),
                          child: _buildFavoriteTile(context, favorites[i]),
                        ),
                      )
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _listController,
                            itemCount: favorites.length,
                            itemBuilder: (context, i) =>
                                _buildFavoriteTile(context, favorites[i]),
                          ),
                          //v1.0 第四阶段："定位当前播放歌曲"悬浮按钮
                          _buildLocateButton(favorites),
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

  /// 收藏歌曲行：星形（取消收藏）+ 添加下一首 + 点击播放
  Widget _buildFavoriteTile(BuildContext context, Song song) {
    return Selector<AudioPlaybackService, String?>(
      selector: (_, p) => p.currentSongId,
      builder: (context, currentId, _) {
        final isCurrent = currentId == song.audioFilePath;
        //当前歌高亮色（v1.0 状态色可自定义，默认强调色）
        final highlight = StatusColors.of(context).currentHighlight;
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
          leading: Icon(
            Icons.music_note,
            color: isCurrent ? highlight : null,
          ),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? highlight : null,
              fontWeight: isCurrent ? FontWeight.bold : null,
            ),
          ),
          subtitle: Text(
            _formatDuration(song.duration),
            //当前播放的歌：时长也用高亮色（与其他页面统一）
            style: TextStyle(color: isCurrent ? highlight : null),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              //取消收藏（实心星；星标色可自定义，默认 amber）
              IconButton(
                iconSize: 22,
                tooltip: '取消收藏',
                icon: Icon(
                  Icons.star,
                  color: StatusColors.of(context).favoriteStar,
                ),
                onPressed: () => _toggleFavorite(context, song),
              ),
              IconButton(
                iconSize: 22,
                tooltip: '添加到下一首',
                //当前播放的歌：添加图标用高亮色；其余用可自定义的添加图标色
                icon: Icon(
                  Icons.playlist_add,
                  color: isCurrent ? highlight : AppIconColors.of(context).add,
                ),
                onPressed: () => _onAddNext(context, song),
              ),
            ],
          ),
          onTap: () => _onSongTap(context, song),
          //v1.0 第三阶段：长按 → 统一长按菜单（含"取消收藏"）
          onLongPress: () => showSongLongPressMenu(context, song),
        );
      },
    );
  }

  /// "定位"悬浮按钮：把正在播放的歌（高亮歌曲）滚动到屏幕中部偏上
  /// （约黄金分割 38.2% 处）。仅当当前歌在本列表（收藏）中时显示。
  Widget _buildLocateButton(List<Song> songs) {
    return LocateCurrentButton(
      songs: songs,
      heroTag: 'locate_current_favorites',
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

  /// 毫秒 → m:ss
  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 从路径提取文件名（不含扩展名）作为收藏页占位行的歌名
  /// （歌曲库暂时缺失时的兜底展示，重扫后由完整歌曲对象替换）
  String _fileNameOf(String path) => p.basenameWithoutExtension(path);
}

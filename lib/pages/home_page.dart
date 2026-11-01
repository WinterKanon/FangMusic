import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../models/app_icon_colors.dart';
import '../models/list_sort_mode.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../models/status_colors.dart';
import '../models/weight_behavior.dart';
import '../pages/about_page.dart';
import '../pages/favorites_page.dart';
import '../pages/home_play_tasks_page.dart';
import '../pages/playlist_detail_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_scanner_service.dart';
import '../services/playlist_service.dart';
import '../services/weight_service.dart';
import '../widgets/app_background.dart';
import '../widgets/bottom_playback_bar_widget.dart';
import '../widgets/left_drawer_widget.dart';
import '../widgets/list_info_bar.dart';
import '../widgets/locate_current_button.dart';
import '../widgets/play_mode_sheet.dart';
import '../widgets/preset_color_picker.dart';
import '../widgets/selection_action_bar.dart';
import '../widgets/song_long_press_menu.dart';
import '../widgets/song_selection_controller.dart';
import '../widgets/song_sort_sheet.dart';

/// 主页：歌曲库列表 + 导入入口 + 播放
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 歌曲列表滚动控制器（v1.0 第四阶段："定位当前播放歌曲"悬浮按钮）
  final ScrollController _listController = ScrollController();

  /// v1.2 多选状态（按勾选顺序）
  final SongSelectionController _selection = SongSelectionController();

  @override
  void dispose() {
    _selection.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    //推迟到首帧绘制完成后加载，避免 build 期间 notifyListeners 触发异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().loadSongs();
      //权限请求也放在这里：界面完全就绪、Activity 已就绪后再弹窗
      _requestPermissions();
    });
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

  /// 多选模式下拖拽：保存自定义顺序；主页顺序与播放队列同步由 Provider 处理
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final library = context.read<LibraryProvider>();
    final songs = List<Song>.of(library.songs);
    if (oldIndex < 0 || oldIndex >= songs.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= songs.length) return;
    final moved = songs.removeAt(oldIndex);
    songs.insert(newIndex, moved);
    await library.setCustomOrder(songs.map((s) => s.audioFilePath).toList());
  }

  /// 申请手机文件读写权限（音频、图片、存储）；异常时忽略不阻塞
  Future<void> _requestPermissions() async {    try {
      //音频读取权限（Android 13+ 对应 READ_MEDIA_AUDIO，低版本对应 READ_EXTERNAL_STORAGE）
      if (await Permission.audio.isDenied) {
        await Permission.audio.request();
      }
      //图片读取权限（用于封面，Android 13+ 对应 READ_MEDIA_IMAGES）
      if (await Permission.photos.isDenied) {
        await Permission.photos.request();
      }
      //存储权限（Android 12 及以下）
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
    } catch (e) {
      debugPrint('[home] 权限请求异常（已忽略）：$e');
    }
  }

  //==================== 导入流程 ====================

  Future<void> _scanFolder() async {
    final library = context.read<LibraryProvider>();
    if (library.isScanning) return;

    //1. 系统文件夹选择器（解析为真实路径）
    final dirPath = await AudioScannerService.pickDirectory();
    if (!mounted) return;
    if (dirPath == null) {
      _showSnackBar('未选择文件夹');
      return;
    }
    if (dirPath.isEmpty) {
      _showSnackBar('暂不支持该位置，请选择手机内部存储中的文件夹（如 Music、Download）');
      return;
    }

    //2. 确认对话框
    final confirmed = await _showConfirmDialog(dirPath);
    if (!mounted) return;
    if (!confirmed) {
      _showSnackBar('已取消选择');
      return;
    }

    //3. 扫描文件夹
    _showSnackBar('正在扫描文件夹...', long: true);
    final result = await library.scanDirectory(dirPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '扫描完成：新增 ${result.added}，移除 ${result.removed}，跳过 ${result.skipped}，失败 ${result.failed}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<bool> _showConfirmDialog(String dirPath) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认扫描文件夹'),
        content: Text('将扫描该文件夹中的音频文件（不包含子文件夹）：\n\n$dirPath'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnackBar(String message, {bool long = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: long ? 30 : 2),
        ),
      );
  }

  //==================== 播放 ====================

  /// 点击歌曲：先确保播放源 = 全部歌曲（若之前在某歌单/收藏页播放过，
  /// 回主页点歌要切回全库队列），再交给播放服务（同歌切播放/暂停，不同歌加载播放）
  Future<void> _onSongTap(Song song) async {
    //切回全部歌曲源（相同源时内部直接忽略，不重建）
    await context.read<PlaylistService>().setPlaySource(PlaySource.allSongs);
    if (!mounted) return;
    final player = context.read<AudioPlaybackService>();
    final ok = await player.toggle(song);
    if (!mounted) return;
    if (!ok) {
      _showSnackBar('播放失败，文件可能已被移动或删除');
    }
  }

  /// "添加下一首"：插入到当前播放的下一首
  void _onAddNext(Song song) {
    final playlist = context.read<PlaylistService>();
    playlist.addNextSong(song.audioFilePath);
    //阶段4："添加下一首"行为调权（+配置值）
    WeightService.instance.applyBehavior(song, WeightBehavior.addNext);
    _showSnackBar('已添加到下一首：${song.name}');
  }

  //==================== 搜索 / 排序 / 主题色（阶段5）====================

  /// 打开搜索页
  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  /// 打开收藏页（v1.0 第四阶段：路由名供"默认停留页面"记录）
  void _openFavorites() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'favorites'),
        builder: (_) => const FavoritesPage(),
      ),
    );
  }

  /// 打开"关于"页（v1.0 第四阶段：app 介绍 / 更新日志 / 联系作者）
  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutPage()),
    );
  }

  /// 打开设置页（v1.0）
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  /// 打开歌单详情页（v1.0 第三阶段；第四阶段加路由名供停留页记录）
  void _openPlaylistDetail(Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: 'playlist:${playlist.id}'),
        builder: (_) => PlaylistDetailPage(playlistId: playlist.id),
      ),
    );
  }

  /// 排序方式弹窗（v1.2：只排当前列表；顺序播放会同步队列）
  Future<void> _showSortSheet() async {
    final library = context.read<LibraryProvider>();
    final selected = await showListSortSheet(
      context,
      current: library.listSortMode,
      options: ListSortMode.homeOptions,
    );
    if (selected == null) return;
    await library.setListSort(selected);
  }

  /// 主题选择弹窗（v1.0）：
  /// 1. 明暗模式三选（日间/夜间/跟随系统，默认跟随系统）
  /// 2. 系统推荐主题色（7 色圆点，当前色高亮对勾）
  /// 3. "更多主题设置…"入口 → 设置页（自定义颜色/背景图）
  Future<void> _showThemePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final theme = ctx.watch<ThemeProvider>();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '主题',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              //明暗模式
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('日间'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('夜间'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('跟随系统'),
                    ),
                  ],
                  selected: {theme.themeMode},
                  onSelectionChanged: (s) => theme.setThemeMode(s.first),
                ),
              ),
              //推荐主题色（默认选项 + 11 色系两级选择）
              Padding(
                padding: const EdgeInsets.all(16),
                child: PresetColorPicker(
                  selected: theme.presetSeed,
                  defaultSelected: theme.isDefaultPreset,
                  onSelect: (c) => theme.setPresetSeed(c),
                ),
              ),
              //更多设置入口
              ListTile(
                leading: Icon(
                  Icons.tune,
                  color: AppIconColors.of(ctx).settings,
                ),
                title: const Text('更多主题设置…'),
                subtitle: const Text('自定义颜色、背景图片与遮罩浓度'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openSettings();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  //==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final mode = context.select((PlaylistService p) => p.mode);
    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeyHome),
        Scaffold(
      //抽屉：扫描入口由抽屉调用；drawerEdgeDragWidth 扩大为屏幕宽的 60%
      //（v1.0 第三阶段优化：从屏幕左侧向右滑的触发区域覆盖屏幕大半）
      drawerEdgeDragWidth: MediaQuery.sizeOf(context).width * 0.6,
      drawer: LeftDrawerWidget(
        onScanFolder: _scanFolder,
        onThemeTap: _showThemePicker,
        onFavoritesTap: _openFavorites,
        onSettingsTap: _openSettings,
        onAboutTap: _openAbout, //v1.0 第四阶段：关于页
        //歌单详情页（v1.0 第三阶段）
        onPlaylistTap: _openPlaylistDetail,
      ),
      appBar: AppBar(
        title: const Text('Music'),
        centerTitle: true,
        actions: [
          //搜索（阶段5；图标色 iconSearch 可自定义）
          IconButton(
            tooltip: '搜索歌曲',
            icon: Icon(Icons.search, color: AppIconColors.of(context).search),
            onPressed: _openSearch,
          ),
        ],
        //v1.2 列表信息栏：播放模式 / 歌曲数 / 排序 / 多选
        bottom: ListInfoBar(
          mode: mode,
          songCount: library.songs.length,
          sortLabel: library.listSortMode.label,
          onModeTap: () => showPlayModeSheet(context),
          onSortTap: _showSortSheet,
          onMultiTap: _toggleSelectionMode,
          multiActive: _selection.isSelecting,
        ),
      ),
      body: Consumer<LibraryProvider>(
        builder: (context, library, _) {
          if (library.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (library.songs.isEmpty) {
            return _buildEmptyState(library);
          }
          final byPath = {
            for (final s in library.songs) s.audioFilePath: s,
          };
          final selectedSongs = <Song>[
            for (final p in _selection.selectedPaths)
              if (byPath[p] != null) byPath[p]!,
          ];
          return Column(
            children: [
              Expanded(child: _buildSongList(library.songs)),
              if (_selection.isSelecting && selectedSongs.isNotEmpty)
                SelectionActionBar(
                  songs: selectedSongs,
                  onFinished: _selection.exit,
                ),
            ],
          );
        },
      ),
      //底部播放栏（可复用组件，全局共享播放状态）；
      //点击栏内的"播放队列"图标（Icons.playlist_play）打开播放队列页
      bottomNavigationBar: BottomPlaybackBarWidget(
        onPlayTasksTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HomePlayTasksPage()),
        ),
      ),
      ),
    ],
    );
  }

  Widget _buildEmptyState(LibraryProvider library) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 72, color: secondary),
          const SizedBox(height: 16),
          const Text('还没有歌曲', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            '点击左上角菜单按钮，选择"选择音乐文件夹"\n自动扫描其中的音乐（不包含子文件夹）',
            style: TextStyle(color: secondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSongList(List<Song> songs) {
    //v1.2 多选模式：可勾选 + 长按拖动自定义顺序
    if (_selection.isSelecting) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: true,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorder: _onReorder,
        itemCount: songs.length,
        itemBuilder: (context, index) => KeyedSubtree(
          key: ValueKey(songs[index].audioFilePath),
          child: _buildSongTile(songs[index], index),
        ),
      );
    }
    //v1.0 第四阶段：下拉刷新——重新扫描已选文件夹，反映歌曲增减变化
    return RefreshIndicator(
      onRefresh: _onRefreshSongs,
      child: Stack(
        children: [
          ListView.builder(
            controller: _listController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: songs.length,
            itemBuilder: (context, index) => _buildSongTile(songs[index], index),
          ),
          //v1.0 第四阶段："定位当前播放歌曲"悬浮按钮
          //（水平：收藏星标列与"添加下一首"按钮列之间；垂直：底部播放栏
          //上边再往上约一个播放栏高度）
          _buildLocateButton(songs),
        ],
      ),
    );
  }

  /// "定位"悬浮按钮：把正在播放的歌（高亮歌曲）滚动到屏幕中部偏上
  /// （约黄金分割 38.2% 处），省去用户逐条翻找。仅当当前歌在本列表
  /// 中时显示（配色/遮罩浓度由主题统一管理）。
  Widget _buildLocateButton(List<Song> songs) {
    return LocateCurrentButton(
      songs: songs,
      heroTag: 'locate_current_home',
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

  /// 下拉刷新：用最近一次选定的文件夹重新扫描（未选过则提示）
  Future<void> _onRefreshSongs() async {
    final library = context.read<LibraryProvider>();
    if (library.folderPath == null) {
      _showSnackBar('尚未选择音乐文件夹：先通过抽屉"选择音乐文件夹"导入');
      return;
    }
    if (library.isScanning) {
      _showSnackBar('正在扫描中，请稍候');
      return;
    }
    final result = await library.refreshScan();
    if (!mounted) return;
    _showSnackBar(
      result == null
          ? '刷新失败（未选择文件夹或正在扫描）'
          : '刷新完成：新增 ${result.added}，移除 ${result.removed}，跳过 ${result.skipped}，失败 ${result.failed}',
    );
  }

  /// 歌曲项：当前播放的歌高亮（Selector 只监听 currentSongId，
  /// 进度条高频刷新不会导致整个列表重建）。
  /// 外层 Consumer 监听 LibraryProvider（收藏/排序变化时刷新星标与序号）。
  Widget _buildSongTile(Song song, int index) {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        //重新取最新歌曲对象（收藏状态可能已变化）
        final latest = library.songs.length > index &&
                library.songs[index].audioFilePath == song.audioFilePath
            ? library.songs[index]
            : library.songs.firstWhere(
                (s) => s.audioFilePath == song.audioFilePath,
                orElse: () => song,
              );
        final isFav = latest.isFavorite;
        if (_selection.isSelecting) {
          final order = _selection.orderOf(latest.audioFilePath);
          final selected = order > 0;
          return ListTile(
            leading: Checkbox(
              value: selected,
              onChanged: (_) => _selection.toggle(latest.audioFilePath),
            ),
            title: Text(
              latest.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: selected ? FontWeight.bold : null,
              ),
            ),
            subtitle: Text(
              selected ? '已选第 $order 首' : _formatDuration(latest.duration),
            ),
            onTap: () => _selection.toggle(latest.audioFilePath),
          );
        }
        return Selector<AudioPlaybackService, String?>(
          selector: (_, p) => p.currentSongId,
          builder: (context, currentId, _) {
            final isCurrent = currentId == latest.audioFilePath;
            //当前歌高亮色（v1.0 状态色可自定义，默认主题色互补色）
            final highlightColor = StatusColors.of(context).currentHighlight;
            return ListTile(
              //最左边：歌曲编号 + 音符图标（编号在 music_note 左边）；
              //当前播放的歌整行（编号/音符/歌名/未收藏星标/添加图标）都用高亮色
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
                  Icon(
                    Icons.music_note,
                    color: isCurrent ? highlightColor : null,
                  ),
                ],
              ),
              title: Text(
                latest.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? highlightColor : null,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                ),
              ),
              subtitle: Text(
                _formatDuration(latest.duration),
                //当前播放的歌时长也用高亮色（与整行其他元素统一）
                style: TextStyle(color: isCurrent ? highlightColor : null),
              ),
              //收藏星标 + "添加下一首"按钮（行尾）
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  //收藏/取消收藏（阶段5，收藏触发 +200 调权；星标色可自定义，默认 amber）。
                  //未收藏的 star_border 在当前播放的歌上显示为高亮色（与其他元素统一）
                  IconButton(
                    iconSize: 22,
                    tooltip: isFav ? '取消收藏' : '收藏',
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav
                          ? StatusColors.of(context).favoriteStar
                          : (isCurrent ? highlightColor : null),
                    ),
                    onPressed: () =>
                        context.read<LibraryProvider>().toggleFavorite(latest),
                  ),
                  //添加下一首：当前播放的歌上图标用高亮色，其余用可自定义的添加图标色
                  IconButton(
                    iconSize: 22,
                    tooltip: '添加到下一首',
                    icon: Icon(
                      Icons.playlist_add,
                      color: isCurrent
                          ? highlightColor
                          : AppIconColors.of(context).add,
                    ),
                    onPressed: () => _onAddNext(latest),
                  ),
                ],
              ),
              onTap: () => _onSongTap(latest),
              //v1.0 第三阶段：长按 → 统一长按菜单（加入歌单…/添加下一首/
              //收藏/设置权重/查看歌曲信息）
              onLongPress: () => showSongLongPressMenu(context, latest),
            );
          },
        );
      },
    );
  }

  /// 毫秒 → m:ss
  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}


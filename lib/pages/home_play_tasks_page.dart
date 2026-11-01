import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../models/play_task.dart';
import '../models/song.dart';
import '../models/status_colors.dart';
import '../providers/library_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/playlist_service.dart';
import '../providers/theme_provider.dart';
import '../services/weight_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_notice.dart';

/// 播放队列页
///
/// 展示当前播放队列（[PlaylistService.tasks]）：
/// - 每项左侧显示**连续排序编号**（1,2,3…）
/// - 当前播放任务高亮（编号/歌名用主题色加粗 + 播放小图标）
/// - 点击任务播放（跳转到该位置）
/// - "添加下一首"插入的任务带橙色"下一首"标记
/// - **进入页面时自动把当前歌曲滚动到屏幕中央偏上**（显眼位置，
///   无需手动滑动查找；上下滑可查看前后歌曲排列）
class HomePlayTasksPage extends StatefulWidget {
  const HomePlayTasksPage({super.key});

  @override
  State<HomePlayTasksPage> createState() => _HomePlayTasksPageState();
}

class _HomePlayTasksPageState extends State<HomePlayTasksPage> {
  /// 列表滚动控制器：进入页面时把当前歌曲滚动到屏幕中央偏上
  final ScrollController _scrollController = ScrollController();

  /// 列表项固定高度（与 ListTile 两行布局高度一致，用于精确计算滚动偏移）
  static const double _itemExtent = 72;

  @override
  void initState() {
    super.initState();
    //首帧绘制完成后，把当前播放的歌曲滚动到屏幕中央偏上。
    //用 ScrollController 直接计算偏移，不依赖列表项是否已构建
    //（ListView.builder 懒加载：第 16 首及之后的项在视口外不会构建，
    //  ensureVisible/GlobalKey 方案会失效）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final idx = context.read<PlaylistService>().currentIndex;
      if (idx < 0) return;
      final pos = _scrollController.position;
      final target = (idx * _itemExtent) - pos.viewportDimension * 0.35;
      _scrollController.animateTo(
        target.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = context.watch<PlaylistService>();
    final library = context.watch<LibraryProvider>();
    final player = context.watch<AudioPlaybackService>();

    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        AppBackground(
            queueKey: ThemePalette.queueSourceKey(
                playlist.source.name, playlist.sourcePlaylistId),
          ),
        Scaffold(
      appBar: AppBar(
        title: const Text('播放队列'),
        centerTitle: true,
      ),
      body: playlist.tasks.isEmpty
          ? const Center(child: Text('队列为空'))
          : ListView.builder(
              controller: _scrollController,
              itemExtent: _itemExtent,
              itemCount: playlist.tasks.length,
              itemBuilder: (context, index) {
                final task = playlist.tasks[index];
                final song = _findSong(library.songs, task.songFilePath);
                final isCurrent =
                    playlist.currentIndex == index &&
                    player.currentSongId == task.songFilePath;
                //当前歌高亮色：与主页一致（状态色 → 当前歌高亮，可自定义，
                //默认主题色互补色/经典模式经典蓝），不用 colorScheme.primary
                final highlightColor = StatusColors.of(context).currentHighlight;
                return ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      //连续排序编号
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrent ? highlightColor : null,
                          fontWeight: isCurrent ? FontWeight.bold : null,
                        ),
                      ),
                      //当前播放小图标
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.graphic_eq, size: 18, color: highlightColor),
                      ],
                    ],
                  ),
                  title: Text(
                    song?.name ?? _fileName(task.songFilePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? highlightColor : null,
                      fontWeight: isCurrent ? FontWeight.bold : null,
                    ),
                  ),
                  subtitle: song != null
                      ? Text(
                          _formatDuration(song.duration),
                          //当前歌的时长也统一用高亮色（与主页一致）
                          style: TextStyle(
                            color: isCurrent ? highlightColor : null,
                          ),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      //v1.1-3（用户 2026-10-29）："下一首"标记由文字改为播放图标。
                      //颜色：自定义（主题颜色→状态色→播放队列下一首）优先，
                      //否则 = 当前主题色（默认主题：日间黑 / 夜间白）
                      if (task.isNextSong)
                        Icon(
                          Icons.play_arrow,
                          size: 18,
                          color: _nextSongMarkColor(context),
                        ),
                      //减号移除按钮（v1.1-2 需求 7）：
                      //点击直接移除 + 权重联动（普通 -5；"下一首"标记歌撤销加分）
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        tooltip: '从队列移除',
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        onPressed: () =>
                            _removeTask(context, index, task, song, isCurrent),
                      ),
                    ],
                  ),
                  onTap: () => player.playAt(index),
                );
              },
            ),
      ),
    ],
    );
  }

  /// "被标记下一首"的标记颜色（v1.1-3）：
  /// 自定义（主题颜色 → 状态色 → 播放队列下一首）优先；
  /// 主题色为**默认**时：主题色本身 = 日白/夜黑，图标取主题色**反色**
  /// → 日间黑 / 夜间白（用户 2026-10-29 复测明确）；
  /// 自定义主题色时：图标与主题色一致。
  Color _nextSongMarkColor(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final custom = theme.palette.colorOf(PaletteItem.queueNext);
    if (custom != null) return Color(custom);
    final accent = theme.seedColor(isDark);
    if (theme.isDefaultPreset) {
      //默认主题：主题色日白夜黑，图标取反色 → 日黑夜白
      return accent.computeLuminance() > 0.5
          ? Colors.black
          : Colors.white;
    }
    return accent;
  }

  /// 队列页"减号"移除任务（v1.1-2 需求 7）：
  /// - 从队列移除该任务（正在播放的任务：继续播放，播完自动切下一首）
  /// - 权重联动：[WeightService.removeFromQueue]——
  ///   普通移除 -5（默认）；移除"添加下一首"标记歌 = 撤销添加时的加分
  void _removeTask(
    BuildContext context,
    int index,
    PlayTask task,
    Song? song,
    bool isCurrent,
  ) {
    PlaylistService.instance.removeTaskAt(index);
    if (song != null) {
      //异步调权（写库内部兜住失败）
      WeightService.instance.removeFromQueue(song, wasNextSong: task.isNextSong);
    }
    final name = song?.name ?? _fileName(task.songFilePath);
    showAppNotice(
      context,
      isCurrent ? '已从队列移除：$name（播完自动切下一首）' : '已从队列移除：$name',
    );
  }

  /// 按路径从库中找歌（找不到返回 null）
  Song? _findSong(List<Song> songs, String path) {
    for (final s in songs) {
      if (s.audioFilePath == path) return s;
    }
    return null;
  }

  /// 路径取最后一段作为兜底显示名
  String _fileName(String path) {
    final idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  /// 毫秒 → m:ss
  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

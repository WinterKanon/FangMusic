import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../models/app_icon_colors.dart';
import '../models/song.dart';
import '../models/status_colors.dart';
import '../models/weight_behavior.dart';
import '../providers/library_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/playlist_service.dart';
import '../services/weight_service.dart';
import '../widgets/app_background.dart';
import '../widgets/bottom_playback_bar_widget.dart';
import '../widgets/song_long_press_menu.dart';
import 'home_play_tasks_page.dart';

/// 搜索页（阶段5）：按歌名实时过滤，点击结果播放并触发
/// "搜索播放"调权（+配置值，阶段4 预留的 onSearchPlay 接口）。
///
/// 搜索播放不叠加"手动点击"调权（避免一次点击双调权）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 点击搜索结果：先切播放源为全部歌曲，再交给播放服务的搜索播放入口（+15 调权）
  Future<void> _onSearchResultTap(Song song) async {
    await context.read<PlaylistService>().setPlaySource(PlaySource.allSongs);
    if (!mounted) return;
    final player = context.read<AudioPlaybackService>();
    final ok = await player.playFromSearch(song);
    if (!mounted) return;
    if (!ok) {
      _showSnackBar('播放失败，文件可能已被移动或删除');
    }
  }

  /// "添加下一首"：插入当前播放的下一首
  void _onAddNext(Song song) {
    final playlist = context.read<PlaylistService>();
    playlist.addNextSong(song.audioFilePath);
    //阶段4："添加下一首"行为调权
    WeightService.instance.applyBehavior(song, WeightBehavior.addNext);
    _showSnackBar('已添加到下一首：${song.name}');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    //按歌名实时过滤（忽略大小写）
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? <Song>[]
        : library.songs
            .where((s) => s.name.toLowerCase().contains(q))
            .toList();

    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeySearch),
        Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: const InputDecoration(
            hintText: '搜索歌曲（按歌名）',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? Center(
              child: Text(
                '输入歌名开始搜索',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          : results.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的歌曲',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) => _buildResultTile(results[i]),
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

  /// 搜索结果行：点击播放（搜索播放调权）；行尾"添加下一首"
  Widget _buildResultTile(Song song) {
    return Selector<AudioPlaybackService, String?>(
      selector: (_, p) => p.currentSongId,
      builder: (context, currentId, _) {
        final isCurrent = currentId == song.audioFilePath;
        //当前歌高亮色（v1.0 状态色可自定义，默认强调色）
        final highlight = StatusColors.of(context).currentHighlight;
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
          subtitle: Text(_formatDuration(song.duration)),
          trailing: IconButton(
            iconSize: 22,
            tooltip: '添加到下一首',
            icon: Icon(
              Icons.playlist_add,
              color: AppIconColors.of(context).add,
            ),
            onPressed: () => _onAddNext(song),
          ),
          onTap: () => _onSearchResultTap(song),
          //v1.0 第三阶段：长按 → 统一长按菜单
          onLongPress: () => showSongLongPressMenu(context, song),
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

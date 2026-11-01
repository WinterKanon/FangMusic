import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_icon_colors.dart';
import '../models/theme_palette.dart';
import '../providers/theme_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/playlist_service.dart';
import '../services/sleep_timer_service.dart';
import '../widgets/app_background.dart';
import '../widgets/play_mode_sheet.dart';
import '../widgets/playback_speed_sheet.dart';
import '../widgets/song_long_press_menu.dart';
import '../widgets/sleep_timer_sheet.dart';
import 'home_play_tasks_page.dart';

/// 播放界面页（v1.2）
///
/// 底部导航：播放模式 / 睡眠定时 / 更多（当前歌曲长按菜单）/ 播放队列；
/// 歌词区域先做占位，后续版本接入。
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _speedText(double s) {
    final text = s == s.roundToDouble()
        ? s.toStringAsFixed(0)
        : s.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return 'x$text 倍';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlaybackService>();
    final playlist = context.watch<PlaylistService>();
    final sleep = context.watch<SleepTimerService>();
    final song = player.currentSong;
    final total = player.duration;
    final pos = player.position > total ? total : player.position;
    final colors = Theme.of(context).colorScheme;
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customAccent = themeProvider.palette.colorOf(PaletteItem.accent);
    //主题色为“默认”时：日间黑、夜间白；自定义/推荐主题色时用对应颜色
    final themeColor = customAccent != null
        ? Color(customAccent)
        : themeProvider.isDefaultPreset
            ? (isDark ? Colors.white : Colors.black)
            : themeProvider.presetSeed;
    //与底部播放栏一致：进度条/播放按钮用“当前歌曲主文字色”与自定义图标色
    final songColor = colors.onSurface;
    final iconColors = AppIconColors.of(context);
    final inactiveTrack = Color.lerp(songColor, colors.surface, 0.65)!;

    return Stack(
      children: [
        const AppBackground(pageKey: ThemePalette.pageKeyPlayer),
        Scaffold(
          appBar: AppBar(
            title: Text(
              song?.name ?? '正在播放',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Icon(Icons.music_note,
                      size: 140,
                      color: song == null
                          ? colors.onSurfaceVariant
                          : themeColor),
                  const SizedBox(height: 28),
                  Text(
                    song?.name ?? '未选择歌曲',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '本地音乐',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  //歌词占位
                  Text('歌词功能将在后续版本开放',
                      style: TextStyle(
                          fontSize: 13, color: colors.onSurfaceVariant)),
                  //把进度/控制整体压到接近底部导航的位置
                  const Spacer(flex: 2),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: songColor,
                      inactiveTrackColor: inactiveTrack,
                      thumbColor: songColor,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      trackHeight: 2,
                    ),
                    child: Slider(
                      value: total.inMilliseconds == 0
                          ? 0
                          : pos.inMilliseconds
                              .clamp(0, total.inMilliseconds)
                              .toDouble(),
                      max: total.inMilliseconds == 0
                          ? 1
                          : total.inMilliseconds.toDouble(),
                      onChanged: song == null
                          ? null
                          : (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos),
                          style: TextStyle(color: colors.onSurfaceVariant)),
                      Text(_fmt(total),
                          style: TextStyle(color: colors.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 40,
                        color: iconColors.previous,
                        tooltip: '上一首',
                        onPressed: song == null ? null : player.playPrevious,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        iconSize: 46,
                        color: iconColors.playPause,
                        tooltip: player.isPlaying ? '暂停' : '播放',
                        onPressed: song == null
                            ? null
                            : (player.isPlaying
                                ? player.pause
                                : player.resume),
                        icon: Icon(player.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        iconSize: 40,
                        color: iconColors.next,
                        tooltip: '下一首',
                        onPressed: song == null ? null : player.playNext,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  //底部导航：模式 / 睡眠 / 更多 / 队列
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _nav(
                          context,
                          playlist.mode.icon,
                          playlist.mode.label,
                          () => showPlayModeSheet(context),
                        ),
                        _nav(
                          context,
                          Icons.speed,
                          _speedText(player.playbackSpeed),
                          () => showPlaybackSpeedSheet(context),
                        ),
                        _nav(
                          context,
                          sleep.active
                              ? Icons.bedtime
                              : Icons.bedtime_outlined,
                          sleep.active ? sleep.remainingLabel : '睡眠定时',
                          () => showSleepTimerSheet(context),
                          active: sleep.active,
                        ),
                        _nav(
                          context,
                          Icons.more_horiz,
                          '更多',
                          song == null
                              ? null
                              : () => showSongLongPressMenu(context, song),
                        ),
                        _nav(
                          context,
                          Icons.queue_music,
                          '播放队列',
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const HomePlayTasksPage()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _nav(BuildContext context, IconData icon, String label,
      VoidCallback? onTap,
      {bool active = false}) {
    final c = active
        ? AppIconColors.of(context).mode
        : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11,
                    color: c,
                    fontWeight: active ? FontWeight.bold : null)),
          ],
        ),
      ),
    );
  }
}

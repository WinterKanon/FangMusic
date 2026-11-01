import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';

import '../models/app_icon_colors.dart';
import '../pages/player_page.dart';
import '../services/audio_playback_service.dart';

/// 底部播放栏（可复用组件）
///
/// 布局参照旧项目：左侧封面图标 + 右侧两行
/// - 第一行：滚动歌名 + 控制按钮（播放模式 / 上一首 / 播放暂停 / 下一首 / 播放队列）
/// - 第二行：当前时间 + 进度条（可拖动）+ 总时长
///
/// 全局共享 [AudioPlaybackService] / [PlaylistService] 状态，无需外部传参。
/// 点击 **Icons.playlist_play（播放队列图标）** 才打开播放队列页（[onPlayTasksTap]），
/// 点击其他区域不触发。
class BottomPlaybackBarWidget extends StatefulWidget {
  const BottomPlaybackBarWidget({super.key, this.onPlayTasksTap});

  /// 点击"播放队列"图标时的回调（打开播放队列页）
  final VoidCallback? onPlayTasksTap;

  @override
  State<BottomPlaybackBarWidget> createState() => _BottomPlaybackBarWidgetState();
}

class _BottomPlaybackBarWidgetState extends State<BottomPlaybackBarWidget> {
  double? _dragValue; //拖动进度条时的临时值（秒），松手后才真正 seek

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlaybackService>();
    //各控制图标独立配色（v1.0：设置 → 主题 → 自定义颜色 → 各图标项）
    final iconColors = AppIconColors.of(context);

    final song = player.currentSong;
    final hasSong = song != null;
    //底部栏封面图标与进度条用"正在播放歌曲（歌名）"的颜色 = 主题主文字色，
    //避免强调色浓度过高（设置 → 主题 → 自定义颜色 → 主文字 可自定义）
    final songColor = Theme.of(context).colorScheme.onSurface;
    //进度条范围：总时长（至少 1 秒，避免 max=0 异常）
    final maxSec = player.duration.inSeconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    //当前秒数：拖动中显示拖动值，松手后回到真实位置
    final currentSec = (_dragValue ?? player.position.inSeconds.toDouble())
        .clamp(0.0, maxSec)
        .toDouble();

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        //surfaceContainer = 底部播放栏自定义颜色（palette.bottomBar）；
        //启用背景图时由主题构建为半透明，透出背景图
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          //① 左侧：封面图标占位（点击进入播放界面页）
          GestureDetector(
            onTap: () => _openPlayer(context),
            child: Icon(
              Icons.music_note,
              size: 50,
              color: songColor,
            ),
          ),
          const SizedBox(width: 12),
          //② 右侧：两行（歌名+控制按钮 / 时间+进度条）
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                //第一行：滚动歌名 + 控制按钮
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      //歌名（外层 SizedBox 提供确定高度：
                      //Marquee 必须有界高度，否则渲染崩溃；
                      //无歌时用普通文本，避免空转动画 Timer）
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openPlayer(context),
                          //歌名上下各留出触发区域（20 → 32）
                          child: SizedBox(
                            height: 32,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: hasSong
                                  ? Marquee(
                                      text: song.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      scrollAxis: Axis.horizontal,
                                      blankSpace: 40,
                                      velocity: 30,
                                      pauseAfterRound:
                                          const Duration(seconds: 2),
                                      startPadding: 8,
                                    )
                                  : Text(
                                      '未选择歌曲',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      //上一首
                      _buildIconButton(
                        icon: Icons.skip_previous,
                        size: 26,
                        color: iconColors.previous,
                        tooltip: '上一首',
                        onPressed: hasSong
                            ? () => player.playPrevious()
                            : null,
                      ),
                      //播放/暂停
                      _buildIconButton(
                        icon: player.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                        color: iconColors.playPause,
                        tooltip: player.isPlaying ? '暂停' : '播放',
                        onPressed: hasSong ? () => player.toggle(song) : null,
                      ),
                      //下一首
                      _buildIconButton(
                        icon: Icons.skip_next,
                        size: 26,
                        color: iconColors.next,
                        tooltip: '下一首',
                        onPressed: hasSong ? () => player.playNext() : null,
                      ),
                      //播放队列（点击此图标打开队列页）
                      _buildIconButton(
                        icon: Icons.playlist_play,
                        size: 26,
                        color: iconColors.queue,
                        tooltip: '播放队列',
                        onPressed: widget.onPlayTasksTap,
                      ),
                    ],
                  ),
                ),
                //第二行：当前时间 + 进度条 + 总时长
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(player.position),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            //已播放部分 = 正在播放歌曲名的主文字色
                            activeTrackColor: songColor,
                            //未播放部分 = 同色的"偏灰/偏淡"版本（去饱和 + 降透明，
                            //黑/白文字色下也可见，随主题色变化而非固定灰色）
                            inactiveTrackColor: _greyishHighlight(songColor),
                            thumbColor: songColor,
                            //圆形进度点调小（默认 10 → 6）
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            //进度条变细（默认 4 → 2）
                            trackHeight: 2,
                          ),
                          child: Slider(
                            value: currentSec,
                            max: maxSec,
                            onChanged: hasSong
                                ? (v) => setState(() => _dragValue = v)
                                : null,
                            onChangeEnd: hasSong
                                ? (v) {
                                    player.seek(Duration(seconds: v.round()));
                                    setState(() => _dragValue = null);
                                  }
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(player.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 统一构建图标按钮（控制间距与点击区域；color = 该图标独立配色）
  Widget _buildIconButton({
    required IconData icon,
    required double size,
    Color? color,
    String? tooltip,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: size + 8, //图标大小+间距
      height: size + 16, //图标大小+间距
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        icon: Icon(icon, size: size, color: color),
        onPressed: onPressed,
      ),
    );
  }

  /// 播放模式选择弹窗（v1.2 共享实现）
  /// 打开播放界面页（v1.2）：点左侧封面图标或歌名
  void _openPlayer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
  }

  /// 时长格式化：mm:ss
  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 高亮/主色的"偏灰"版本：饱和度降到 25%，再降透明度到 35%。
  /// 未播放的进度条轨道用它——有颜色但偏灰偏淡（随主题色变化，而非固定灰色）
  Color _greyishHighlight(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation(hsl.saturation * 0.25)
        .toColor()
        .withValues(alpha: 0.35);
  }
}

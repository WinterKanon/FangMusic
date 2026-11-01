import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/theme_provider.dart';
import '../services/audio_playback_service.dart';

/// 悬浮"定位当前播放歌曲"按钮（v1.0 第四阶段）。
///
/// - **位置**：水平在"收藏星标列"与"添加下一首"按钮列之间（right: 44）、
///   垂直在底部播放栏上边再往上约一个播放栏高度（bottom: 140）；
/// - **显示**：仅当当前播放的歌就在 [songs] 列表中时显示（切源/切页自动隐藏）；
/// - **作用**：点击后由宿主页面把当前播放歌滚动到视口约 38.2%（黄金分割）处；
/// - **配色**（v1.1-3，用户 2026-10-28 拍板）：背景/文字可在
///   "设置 → 主题颜色 → 强调与图标"自定义；默认背景 = 强调色（主题色）、
///   默认文字 = 强调色反色（按亮度取对比色）。不再有遮罩浓度设置。
class LocateCurrentButton extends StatelessWidget {
  const LocateCurrentButton({
    super.key,
    required this.songs,
    required this.onScrollTo,
    this.heroTag,
  });

  /// 本页面的歌曲列表（用于判断当前歌是否在其中、算出所在位置）
  final List<Song> songs;

  /// 由宿主页面执行的滚动定位（入参 = 当前歌在 [songs] 中的索引）
  final ValueChanged<int> onScrollTo;

  /// Hero 标签（每页唯一，避免同屏多个按钮 Hero 冲突）
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Selector<AudioPlaybackService, String?>(
      selector: (_, p) => p.currentSongId,
      builder: (context, currentId, _) {
        if (currentId == null) return const SizedBox.shrink();
        final idx = songs.indexWhere((s) => s.audioFilePath == currentId);
        if (idx < 0) return const SizedBox.shrink();
        //v1.1-3：背景默认 = 主题色；文字默认 = 主题色反色（无遮罩混合）
        final bg = theme.locateButtonBackground(isDark);
        final fg = theme.locateButtonText(isDark);
        return Positioned(
          right: 44, //收藏星标列与"添加下一首"按钮列之间
          bottom: 140, //距底部播放栏上边约一个播放栏高度
          child: Hero(
            tag: heroTag ?? 'locate_current',
            child: Material(
              color: bg,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onScrollTo(idx),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.center_focus_strong,
                    size: 22,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

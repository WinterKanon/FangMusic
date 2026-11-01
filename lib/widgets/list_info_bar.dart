import 'package:flutter/material.dart';

import '../models/play_mode.dart';

/// 列表信息栏（v1.2）
///
/// 放在主页/收藏/自定义歌单页 AppBar 的 bottom：左侧播放模式、歌曲数、
/// 排序方式，右侧多选。点击模式/排序弹窗由页面传入。
class ListInfoBar extends StatelessWidget implements PreferredSizeWidget {
  const ListInfoBar({
    super.key,
    required this.mode,
    required this.songCount,
    required this.sortLabel,
    required this.onModeTap,
    required this.onSortTap,
    this.onMultiTap,
    this.multiActive = false,
  });

  final PlayMode mode;
  final int songCount;
  final String sortLabel;
  final VoidCallback onModeTap;
  final VoidCallback onSortTap;
  final VoidCallback? onMultiTap;
  final bool multiActive;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    //与歌曲标题等主文字同浓度（onSurface），不再用偏淡的 onSurfaceVariant
    final secondary = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _BarButton(
            icon: mode.icon,
            label: mode.label,
            color: secondary,
            onTap: onModeTap,
            tooltip: '播放模式',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '共 $songCount 首',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ),
          _BarButton(
            icon: Icons.sort,
            label: sortLabel,
            color: secondary,
            onTap: onSortTap,
            tooltip: '排序方式',
          ),
          IconButton(
            tooltip: '多选',
            icon: Icon(
              Icons.checklist,
              color: multiActive ? primary : secondary,
            ),
            onPressed: onMultiTap,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

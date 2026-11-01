import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

/// 单个作用范围（页面 / 播放源 / 歌单）的背景设置板块（v1.1-3）
///
/// 结构自上而下：
/// 1. **页面预览图**：模拟该页面形态（AppBar 条 + 列表占位 + 页面名），
///    实时套用"生效背景图 + 当前明暗遮罩"，换图/调浓度即时变化；
/// 2. 左右并排"从相册选择" / "从文件管理器选择"；
/// 3. 背景图遮罩浓度（日间调节条 / 夜间调节条，0%–100%）；
/// 4. 历史背景图片（若已单独设置背景，标题行右侧有"移除当前背景"）；
/// 5. 历史背景图片涂片（横向滚动，点击选用）。
///
/// 取背景/遮罩走 ThemeProvider.effectiveBackgroundPath / Mask：
/// 未单独设置时回退全局默认（预览同样反映回退效果）。
class PageBackgroundSection extends StatelessWidget {
  const PageBackgroundSection({
    super.key,
    required this.scopeKey,
    required this.title,
  });

  /// 作用范围 Key（页面 Key / queue:xx / pl:歌单id）
  final String scopeKey;

  /// 页面显示名（预览卡片中央 + 标题辅助）
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    //生效配置（未单独设置 → 回退全局）
    final bgPath = theme.effectiveBackgroundPath(scopeKey);
    final maskDay = theme.effectiveBackgroundMask(scopeKey, false);
    final maskNight = theme.effectiveBackgroundMask(scopeKey, true);
    //是否"单独设置了背景图"（决定"移除当前背景"按钮是否显示）
    final hasOwnImage =
        theme.backgroundConfigFor(scopeKey)?.imagePath != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        //1. 页面预览（实时反映当前生效背景 + 当前明暗遮罩）
        _buildPreview(context, theme, bgPath, isDark ? maskNight : maskDay),
        const SizedBox(height: 12),
        //2. 选图按钮（左右并排）
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    _import(context, theme, fromFiles: false),
                icon: const Icon(Icons.photo_library),
                label: const Text('从相册选择'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _import(context, theme, fromFiles: true),
                icon: const Icon(Icons.folder_open),
                label: const Text('从文件管理器'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        //"移除当前背景"：仅在该范围单独设置了背景图时显示
        if (hasOwnImage)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => theme.setPageBackgroundPath(scopeKey, null),
              child: const Text('移除当前背景'),
            ),
          ),
        const SizedBox(height: 4),
        //3. 遮罩浓度（日/夜分开调节；未单独设置时滑块显示全局值，
        //   拖动即创建本范围独立配置）
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('背景图遮罩浓度（日间白 / 夜间黑，100% = 不显示背景图）'),
        ),
        _buildAlphaSlider(
          context,
          label: '日间',
          value: maskDay,
          onChanged: (v) => theme.setPageMask(scopeKey, isDark: false, alpha: v),
        ),
        _buildAlphaSlider(
          context,
          label: '夜间',
          value: maskNight,
          onChanged: (v) => theme.setPageMask(scopeKey, isDark: true, alpha: v),
        ),
        const SizedBox(height: 16),
        //4/5. 历史背景图片（标题行右侧"移除当前背景"已放上面；
        //      列表复用全局历史图片，点击设为该范围背景）
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('历史背景图片'),
        ),
        FutureBuilder<List<String>>(
          future: theme.listHistoryBackgrounds(),
          builder: (context, snapshot) {
            final paths = snapshot.data ?? [];
            if (paths.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有历史背景图',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              );
            }
            //v1.1-3（用户 2026-10-28）：多行排列（Wrap 自动换行）
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in paths)
                  _buildHistoryItem(context, theme, path),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 页面预览卡片：模拟页面骨架 + 生效背景图 + 遮罩
  Widget _buildPreview(
    BuildContext context,
    ThemeProvider theme,
    String? bgPath,
    double maskAlpha,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            //背景图（回退全局图；无图 → 默认底色）
            if (bgPath != null)
              Image.file(
                File(bgPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
              ),
            //遮罩（当前明暗浓度实时叠加）
            ColoredBox(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withValues(alpha: maskAlpha)
                  : Colors.white.withValues(alpha: maskAlpha),
            ),
            //模拟 AppBar 条
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 36,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Container(
                  width: 90,
                  height: 12,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            //列表占位行
            Positioned(
              top: 52,
              left: 16,
              right: 16,
              child: Column(
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: scheme.onSurface
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            //页面名（中央）
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            //右上角"已单独设置"标记（可选提示）
            if (theme.backgroundConfigFor(scopeKey)?.imagePath != null)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '已单独设置',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 遮罩浓度滑块（带明暗标签 + 百分比）
  Widget _buildAlphaSlider(
    BuildContext context, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(value: value, onChanged: onChanged),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Future<void> _import(
    BuildContext context,
    ThemeProvider theme, {
    required bool fromFiles,
  }) async {
    final newPath = fromFiles
        ? await theme.importBackgroundForKeyFromFiles(scopeKey)
        : await theme.importBackgroundForKeyFromGallery(scopeKey);
    if (!context.mounted) return;
    if (newPath == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('未选择图片或导入失败')));
    }
  }

  Widget _buildHistoryItem(BuildContext context, ThemeProvider theme, String path) {
    final isCurrent = theme.effectiveBackgroundPath(scopeKey) == path;
    return GestureDetector(
      onTap: () => theme.setPageBackgroundPath(scopeKey, path),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(path),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 80,
                height: 80,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          //当前标记（该范围正在使用）
          if (isCurrent)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('当前',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
          //删除按钮（删除历史图文件；不影响歌曲）
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () => _confirmDelete(context, theme, path),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, ThemeProvider theme, String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除背景图片'),
        content: const Text('确定删除这张历史背景图片吗？（不会影响歌曲文件）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await theme.deleteBackgroundImage(path);
    }
  }
}

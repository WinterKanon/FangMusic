import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_background.dart';
import 'page_backgrounds_page.dart';

/// 背景图片设置详情页（设置 → 背景图片）
///
/// - **明暗模式**：日间 / 夜间 / 跟随系统（与主题页同一板块，复制于此方便切换）
/// - 当前背景预览（无图显示默认）
/// - 选图入口：**从相册选择**（系统图库）/ **从文件管理器选择**（系统文件管理器，
///   过滤图片扩展名，类似选音乐文件夹）；选图后进入系统裁剪界面，可裁剪
/// - **移除当前背景**：仅解除当前背景（历史图片保留，可随时重新点选）
/// - **透明度调节**：遮罩不透明度滑块（0% 无遮罩 ~ 100% 全黑，默认 30%），实时生效
/// - 历史背景图片：横向列表，点击设为当前、右上角删除（删除当前图自动回退默认）
class BackgroundSettingsPage extends StatelessWidget {
  const BackgroundSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
      appBar: AppBar(title: const Text('背景图片与遮罩浓度'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          //明暗模式（与主题页同一板块；明暗影响遮罩观感，放顶部便于切换）
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('明暗模式'),
          ),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('日间')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('夜间')),
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('跟随系统')),
            ],
            selected: {theme.themeMode},
            onSelectionChanged: (s) => theme.setThemeMode(s.first),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('当前背景'),
          ),
          //当前背景预览
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: theme.palette.backgroundImagePath == null
                ? const Center(child: Text('当前为默认背景（无图片）'))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(theme.palette.backgroundImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Center(child: Text('图片不存在')),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _import(context, fromFiles: false),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('从相册选择'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _import(context, fromFiles: true),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('从文件管理器'),
                ),
              ),
            ],
          ),
          if (theme.palette.hasBackgroundImage) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => theme.setBackgroundImage(null),
                child: const Text('移除当前背景'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          //透明度调节（遮罩浓度，日间/夜间分别调节）：
          //**日间 = 白色遮罩**：值越大背景越白，100% 时背景全白（等同未设置背景图）
          //**夜间 = 黑色遮罩**：值越大背景越黑，100% 时背景全黑（等同未设置背景图）
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('背景图遮罩浓度（日间白 / 夜间黑，100% = 不显示背景图）'),
          ),
          _buildAlphaSlider(
            context,
            label: '日间',
            value: theme.palette.backgroundOverlayAlphaLight,
            onChanged: (v) => theme.setBackgroundOverlayAlphaLight(v),
          ),
          _buildAlphaSlider(
            context,
            label: '夜间',
            value: theme.palette.backgroundOverlayAlphaDark,
            onChanged: (v) => theme.setBackgroundOverlayAlphaDark(v),
          ),
          const SizedBox(height: 8),
          //抽屉栏遮罩浓度（v1.0 第三阶段修复）：单独调节抽屉栏不透明度，
          //与背景遮罩同一语义——日间白遮罩/夜间黑遮罩，值越大越不透明，
          //100% = 抽屉全白/全黑（等同未设置背景图）
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text('抽屉栏遮罩浓度（日间白 / 夜间黑，100% = 不透明）'),
          ),
          _buildAlphaSlider(
            context,
            label: '日间',
            value: theme.palette.drawerOverlayAlphaLight,
            onChanged: (v) => theme.setDrawerOverlayAlphaLight(v),
          ),
          _buildAlphaSlider(
            context,
            label: '夜间',
            value: theme.palette.drawerOverlayAlphaDark,
            onChanged: (v) => theme.setDrawerOverlayAlphaDark(v),
          ),
          const SizedBox(height: 16),
          //v1.1-3：删除"悬浮定位按钮遮罩浓度"设置（用户 2026-10-28 拍板：
          //设计上有问题）——定位按钮配色统一走"主题颜色 → 强调与图标"。
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
              //v1.1-3（用户 2026-10-28）：多行排列（Wrap 自动换行），
              //避免只有一行时用户误以为多余历史图被删掉
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
          const SizedBox(height: 16),
          //设置各页面背景图片入口（v1.1-3）：底部新增板块。
          //v1.1-3（用户 2026-10-29 重新详述）：入口背景改**透明**
          //（与设置页其他入口一致，页面背景层保留）
          Card(
            margin: EdgeInsets.zero,
            color: Colors.transparent,
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.grid_view),
              title: const Text('设置各页面背景图片'),
              subtitle: const Text('为主页/收藏/歌单/播放队列/搜索/设置/JSON/关于分别设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PageBackgroundsPage()),
              ),
            ),
          ),
        ],
      ),
      ),
    ],
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

  Future<void> _import(BuildContext context, {required bool fromFiles}) async {    final theme = context.read<ThemeProvider>();
    final newPath = fromFiles
        ? await theme.importBackgroundFromFiles()
        : await theme.importBackgroundFromGallery();
    if (!context.mounted) return;
    if (newPath == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('未选择图片或导入失败')));
    }
  }

  Widget _buildHistoryItem(BuildContext context, ThemeProvider theme, String path) {
    final isCurrent = theme.palette.backgroundImagePath == path;
    return GestureDetector(
      onTap: () => theme.setBackgroundImage(path),
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
          //当前标记
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
          //删除按钮
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_background.dart';
import 'playlist_backgrounds_page.dart';
import 'single_scope_background_page.dart';

/// 设置各页面背景图片页（v1.1-3）
///
/// 入口：设置 → 背景图片与遮罩浓度 → 底部"设置各页面背景图片"。
/// 板块自上而下：主页 / 收藏页 / 自定义歌单页（二级入口）/ 播放队列页
/// （源级子项）/ 搜索页 / 设置页（多数子页共用，JSON 例外）/ JSON /
/// 关于页。每个板块点击进入对应作用范围的背景设置（含实时预览）。
class PageBackgroundsPage extends StatelessWidget {
  const PageBackgroundsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    //v1.1-3（用户 2026-10-29）：回退上轮"背景透明"改动（用户将重新详述方案），
    //恢复与旧设置入口一致的 settingsPages 页面背景
    return Stack(
      children: [
        const AppBackground(pageKey: 'settingsPages'),
        Scaffold(
      appBar: AppBar(title: const Text('设置各页面背景图片'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  '未单独设置的页面统一使用全局默认背景图；点击板块为对应页面单独设置背景与遮罩浓度。',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              _scopeTile(
                context,
                icon: Icons.home,
                title: '主页',
                scopeKey: ThemePalette.pageKeyHome,
              ),
              _scopeTile(
                context,
                icon: Icons.star,
                title: '我的收藏页',
                scopeKey: ThemePalette.pageKeyFavorites,
              ),
              _scopeTile(
                context,
                icon: Icons.play_circle_outline,
                title: '播放详情页',
                subtitle: '播放界面（封面/进度/倍速/睡眠/队列）',
                scopeKey: ThemePalette.pageKeyPlayer,
              ),
              //自定义歌单页（二级入口）。
              //v1.1-3（用户 2026-10-29 复测）：该入口与播放队列板块漏改，补透明
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.transparent,
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: const Text('自定义歌单页'),
                  subtitle: const Text('为每个自定义歌单分别设置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PlaylistBackgroundsPage()),
                  ),
                ),
              ),
              //播放队列页（单页面 + 按播放源切背景：源级子项）。
              //v1.1-3（用户 2026-10-29 复测）：本板块卡片漏改，补透明（含内部子项）
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.transparent,
                elevation: 0,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: const Text('播放队列页'),
                      subtitle: const Text('单页面，按播放源切换背景'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _sourceTile(
                      context,
                      title: '全部播放源',
                      scopeKey: ThemePalette.pageKeyQueue,
                    ),
                    _sourceTile(
                      context,
                      title: '主页播放源',
                      scopeKey: ThemePalette.queueSourceAllSongs,
                    ),
                    _sourceTile(
                      context,
                      title: '收藏播放源',
                      scopeKey: ThemePalette.queueSourceFavorites,
                    ),
                    ListTile(
                      title: const Text('各歌单源'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PlaylistBackgroundsPage(useQueuePrefix: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _scopeTile(
                context,
                icon: Icons.search,
                title: '搜索页',
                scopeKey: ThemePalette.pageKeySearch,
              ),
              _scopeTile(
                context,
                icon: Icons.settings,
                title: '设置页（多数子页共用）',
                subtitle: '主题颜色 / 背景图片 / 权重调节 / 更新日志 / 使用介绍等',
                scopeKey: ThemePalette.pageKeySettingsPages,
              ),
              _scopeTile(
                context,
                icon: Icons.data_object,
                title: 'JSON 数据内容页',
                subtitle: '例外，独立设置',
                scopeKey: ThemePalette.pageKeyJsonData,
              ),
              _scopeTile(
                context,
                icon: Icons.info_outline,
                title: '关于页',
                scopeKey: ThemePalette.pageKeyAbout,
              ),
              const SizedBox(height: 12),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: theme.hasPageBackgroundOverrides
                          ? () => _confirmClearAll(context)
                          : null,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清除各页面的自定义设置'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '仅清除页面 / 歌单 / 播放源单独设置的背景与遮罩，'
                      '全部回退全局背景；不会删除全局背景与历史背景图片。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  /// 二次确认后清除全部页面级自定义（背景 + 遮罩）
  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除各页面的自定义设置'),
        content: const Text(
          '将清除主页、收藏页、播放详情页、自定义歌单、播放队列各播放源、搜索页、'
          '设置页、JSON 页、关于页单独设置的背景图片与遮罩浓度，'
          '全部恢复为全局背景。\n\n'
          '不会删除全局背景图，也不会删除历史背景图片。\n\n'
          '确定清除吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<ThemeProvider>().clearAllPageBackgrounds();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除各页面的自定义设置')),
    );
  }

  /// 常规板块（页面级）
  Widget _scopeTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required String scopeKey,
  }) {
    final theme = context.watch<ThemeProvider>();
    final hasOwn = theme.backgroundConfigFor(scopeKey)?.imagePath != null;
    //v1.1-3（用户 2026-10-29 重新详述）：入口背景透明（页面背景层保留）
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.transparent,
      elevation: 0,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null
            ? Text(hasOwn ? '已单独设置' : '使用全局背景',
                style: const TextStyle(fontSize: 12))
            : Text(subtitle,
                style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                SingleScopeBackgroundPage(scopeKey: scopeKey, title: title),
          ),
        ),
      ),
    );
  }

  /// 播放队列源级子项
  Widget _sourceTile(
    BuildContext context, {
    required String title,
    required String scopeKey,
  }) {
    final theme = context.watch<ThemeProvider>();
    final hasOwn = theme.backgroundConfigFor(scopeKey)?.imagePath != null;
    return ListTile(
      dense: true,
      leading: const SizedBox(width: 24),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasOwn ? '已单独设置' : '使用全局',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SingleScopeBackgroundPage(scopeKey: scopeKey, title: title),
        ),
      ),
    );
  }
}

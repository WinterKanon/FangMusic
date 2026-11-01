import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../providers/playlist_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_background.dart';
import 'single_scope_background_page.dart';

/// 自定义歌单背景设置子页（v1.1-3）
///
/// 两种用途（[useQueuePrefix] 区分）：
/// - false：为每个自定义歌单设置背景 → 作用范围 Key = `pl:<歌单id>`
///   （对应"设置各页面背景图片 → 自定义歌单页"入口）；
/// - true：为播放队列页"各歌单源"设置背景 → Key = `queue:pl:<歌单id>`
///   （对应"播放队列页板块 → 各歌单源"入口）。
class PlaylistBackgroundsPage extends StatelessWidget {
  const PlaylistBackgroundsPage({
    super.key,
    this.useQueuePrefix = false,
  });

  /// true = 作为播放队列"各歌单源"子入口（Key 带 queue: 前缀）
  final bool useQueuePrefix;

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>().playlists;
    final theme = context.watch<ThemeProvider>();
    //v1.1-3（用户 2026-10-29）：回退上轮"背景透明"改动（用户将重新详述方案），
    //恢复与旧设置入口一致的 settingsPages 页面背景
    return Stack(
      children: [
        const AppBackground(pageKey: 'settingsPages'),
        Scaffold(
      appBar: AppBar(
        title: Text(useQueuePrefix ? '播放队列·各歌单源' : '自定义歌单背景'),
        centerTitle: true,
      ),
          body: playlists.isEmpty
              ? const Center(child: Text('还没有自定义歌单\n先在抽屉底部点击"新建歌单"创建'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '点击歌单为其单独设置背景图与遮罩浓度；未设置的歌单沿用全局默认背景。',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    for (final p in playlists)
                      //v1.1-3（用户 2026-10-29 重新详述）：子入口背景透明（页面背景层保留）
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.transparent,
                        elevation: 0,
                        child: ListTile(
                          leading: const Icon(Icons.playlist_play),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${p.songFilePaths.length} 首'),
                          trailing: _buildStateBadge(
                            context,
                            theme,
                            useQueuePrefix
                                ? ThemePalette.queueSourceKey(
                                    'playlist', p.id)
                                : ThemePalette.playlistKey(p.id),
                          ),
                          onTap: () => _pushDetail(context, p.id, p.name),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 右侧状态徽标：已单独设置 / 使用全局
  Widget _buildStateBadge(
      BuildContext context, ThemeProvider theme, String scopeKey) {
    final hasOwn = theme.backgroundConfigFor(scopeKey)?.imagePath != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hasOwn
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        hasOwn ? '已单独设置' : '使用全局',
        style: TextStyle(
          fontSize: 11,
          color: hasOwn
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _pushDetail(BuildContext context, String playlistId, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SingleScopeBackgroundPage(
          scopeKey: useQueuePrefix
              ? ThemePalette.queueSourceKey('playlist', playlistId)
              : ThemePalette.playlistKey(playlistId),
          title: '$name · 背景',
        ),
      ),
    );
  }
}

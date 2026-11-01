import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../models/weight_behavior.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/playback_stats_service.dart';
import '../services/playlist_service.dart';
import '../services/weight_config_service.dart';
import '../services/weight_service.dart';
import 'app_notice.dart';
import 'song_weight_dialog.dart';

/// 长按歌曲统一菜单（v1.0 第三阶段）
///
/// 菜单项全集（播放队列页除外，该页不弹菜单）：
/// 1. 加入歌单…（子弹窗列出全部自定义歌单，点击加入；已在歌单中则提示）
/// 2. 添加到下一首（插入当前歌之后 + "添加下一首"调权）
/// 3. 收藏 / 取消收藏（星标开关，收藏/取消收藏双向调权）
/// 4. 标记不喜欢（v1.1-2：基准权重降配置值 + 当前权重减配置值，含二次确认）
/// 5. 设置权重…（复用 [SongWeightDialog]；trailing 显示当前 + 基准权重）
/// 6. 查看歌曲信息（名字、位置、编号、时长、权重值、文件大小、添加时间）
/// 7. 移除歌单（**仅歌单详情页**显示：把该歌从当前歌单移除）
/// 8. 删除歌曲（v1.1-2，红色置底：删本地文件 + 同步歌曲库/收藏/歌单/队列/权重）
///
/// 主页/搜索页/收藏页/歌单详情页统一调用本函数，保证菜单行为一致。
Future<void> showSongLongPressMenu(
  BuildContext context,
  Song song, {
  bool inPlaylistDetail = false,
  String? playlistId,
}) async {
  //菜单动作值
  const kAddToPlaylist = 'addToPlaylist';
  const kAddNext = 'addNext';
  const kToggleFavorite = 'toggleFavorite';
  const kMarkUnlike = 'markUnlike';
  const kSetWeight = 'setWeight';
  const kInfo = 'info';
  const kRemoveFromPlaylist = 'removeFromPlaylist';
  const kDeleteSong = 'deleteSong';

  //收藏状态取最新（用户可能刚在别处操作过）
  final library = context.read<LibraryProvider>();
  final latest = library.songs.firstWhere(
    (s) => s.audioFilePath == song.audioFilePath,
    orElse: () => song,
  );
  final isFav = latest.isFavorite;

  final selected = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          //标题：歌曲名（过长省略）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.music_note, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          //1. 加入歌单…
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('加入歌单…'),
            onTap: () => Navigator.of(ctx).pop(kAddToPlaylist),
          ),
          //2. 添加到下一首
          ListTile(
            leading: const Icon(Icons.queue_play_next),
            title: const Text('添加到下一首'),
            onTap: () => Navigator.of(ctx).pop(kAddNext),
          ),
          //3. 收藏 / 取消收藏（文字随当前状态）
          ListTile(
            leading: Icon(
              isFav ? Icons.star : Icons.star_border,
              color: isFav ? Colors.amber : null,
            ),
            title: Text(isFav ? '取消收藏' : '收藏'),
            onTap: () => Navigator.of(ctx).pop(kToggleFavorite),
          ),
          //4. 标记不喜欢（v1.1-2：基准降配置值 + 当前权重减配置值）
          ListTile(
            leading: Icon(
              Icons.thumb_down_outlined,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              '标记不喜欢',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () => Navigator.of(ctx).pop(kMarkUnlike),
          ),
          //5. 设置权重…（trailing 显示当前歌曲权重值，方便直接查看）
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('设置权重…'),
            trailing: Text(
              '当前 ${(WeightService.instance.weightOf(song.audioFilePath) ?? 100.0).round()} · '
              '基准 ${(WeightService.instance.baseWeightOf(song.audioFilePath) ?? 100.0).round()}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () => Navigator.of(ctx).pop(kSetWeight),
          ),
          //6. 查看歌曲信息
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('查看歌曲信息'),
            onTap: () => Navigator.of(ctx).pop(kInfo),
          ),
          //7. 移除歌单（仅歌单详情页）
          if (inPlaylistDetail)
            ListTile(
              leading: Icon(
                Icons.playlist_remove,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                '移除歌单',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.of(ctx).pop(kRemoveFromPlaylist),
            ),
          const Divider(height: 1),
          //8. 删除歌曲（红色置底，v1.1-2）
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text(
              '删除歌曲',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () => Navigator.of(ctx).pop(kDeleteSong),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (selected == null || !context.mounted) return;
  switch (selected) {
    case kAddToPlaylist:
      await _showAddToPlaylistSheet(context, song);
    case kAddNext:
      _onAddNext(context, song);
    case kToggleFavorite:
      await context.read<LibraryProvider>().toggleFavorite(latest);
    case kMarkUnlike:
      await _confirmMarkUnlike(context, latest);
    case kSetWeight:
      await _showWeightDialog(context, song);
    case kInfo:
      await _showSongInfoDialog(context, song);
    case kRemoveFromPlaylist:
      await _confirmRemoveFromPlaylist(context, song, playlistId);
    case kDeleteSong:
      await _confirmDeleteSong(context, latest);
  }
}

//==================== 加入歌单… ====================

/// 加入歌单子弹窗：列出全部自定义歌单，点击即加入（幂等）
Future<void> _showAddToPlaylistSheet(BuildContext context, Song song) async {
  final provider = context.read<PlaylistProvider>();
  final playlists = provider.playlists;
  final selected = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '加入歌单',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          if (playlists.isEmpty)
            const ListTile(
              leading: Icon(Icons.queue_music),
              title: Text('还没有自定义歌单'),
              subtitle: Text('先在抽屉底部点击"新建歌单"创建'),
              enabled: false,
            ),
          for (final p in playlists)
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${p.songFilePaths.length} 首'),
              onTap: () => Navigator.of(ctx).pop(p.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  final ok = context
      .read<PlaylistProvider>()
      .addSongToPlaylist(selected, song.audioFilePath);
  _showSnackBar(context, ok ? '已加入歌单：${song.name}' : '这首歌已在歌单中');
}

//==================== 添加到下一首 ====================

void _onAddNext(BuildContext context, Song song) {
  context.read<PlaylistService>().addNextSong(song.audioFilePath);
  //"添加下一首"行为调权（+配置值）
  WeightService.instance.applyBehavior(song, WeightBehavior.addNext);
  _showSnackBar(context, '已添加到下一首：${song.name}');
}

//==================== 设置权重… ====================

Future<void> _showWeightDialog(BuildContext context, Song song) async {
  final result = await showDialog<Object>(
    context: context,
    builder: (_) => SongWeightDialog(song: song),
  );
  if (!context.mounted) return;
  if (result == true) {
    _showSnackBar(context, '已重置该曲权重为 100');
  } else if (result is double) {
    _showSnackBar(context, '已设置权重：${result.round()}');
  }
}

//==================== 查看歌曲信息 ====================

Future<void> _showSongInfoDialog(BuildContext context, Song song) async {
  final weight = WeightService.instance.weightOf(song.audioFilePath) ?? 100.0;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      //未设置背景图时，真机上对话框偶发透出黑色路由底；显式给不透明背景
      backgroundColor:
          Theme.of(ctx).colorScheme.surfaceContainerHigh.a == 0
              ? Theme.of(ctx).colorScheme.surface
              : Theme.of(ctx).colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Expanded(
            child: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            '播放 ${PlaybackStatsService.instance.countOf(song.audioFilePath)} 次',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('位置', song.audioFilePath),
          _infoRow('编号', '${song.sortNumber}'),
          _infoRow('时长', _formatDuration(song.duration)),
          _infoRow('权重值', '${weight.round()}'),
          _infoRow('文件大小', _formatSize(song.fileSize)),
          _infoRow('添加时间', song.addTime),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}

//==================== 标记不喜欢（v1.1-2）====================

/// 标记不喜欢：二次确认后，基准权重降为配置值（默认 60）、
/// 当前权重减配置值（默认 50）。7 天回归的目标随后 = 新基准。
Future<void> _confirmMarkUnlike(BuildContext context, Song song) async {
  final config = WeightConfigService.instance;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('标记不喜欢'),
      content: Text(
        '将降低「${song.name}」的权重：\n'
        '· 基准权重降为 ${config.unlikeBaseWeight.round()}\n'
        '· 当前权重减 ${config.unlikeDelta.abs().round()}\n'
        '（可在 设置 → 权重调节 中自定义）',
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
          child: const Text('标记'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await WeightService.instance.markUnliked(song);
  if (!context.mounted) return;
  _showSnackBar(context, '已标记不喜欢：${song.name}');
}

//==================== 删除歌曲（v1.1-2）====================

/// 删除歌曲：二次确认 → 删磁盘文件（失败仅移出库并提示）→
/// 同步清理歌曲库 / 收藏集 / 全部歌单 / 播放队列任务 / 权重记录。
///
/// 正在播放被删歌曲：不打断当前播放（音频已加载），播完自动切下一首；
/// 删除导致加载失败时由播放服务自动跳下一首（既有容错）。
Future<void> _confirmDeleteSong(BuildContext context, Song song) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除歌曲'),
      content: Text(
        '将从设备删除该音频文件，**不可恢复**。\n'
        '确定删除「${song.name}」吗？',
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
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  //Provider 引用与路径先取（后续 await 后不再触碰 context）
  final library = context.read<LibraryProvider>();
  final playlistProvider = context.read<PlaylistProvider>();
  final path = song.audioFilePath;
  //1. 删除磁盘文件（v1.1 增强：Android 11+ 需"所有文件访问"权限；
  //   未授权 → 引导去系统授权，返回后自动重试；失败/拒绝 → 降级仅移出库）
  var fileDeleted = true;
  try {
    final f = File(path);
    if (await f.exists()) {
      if (Platform.isAndroid &&
          !await Permission.manageExternalStorage.isGranted) {
        //Android 11+ 未授权（Android 10 及以下该权限恒 granted，不会进入）
        if (!context.mounted) {
          fileDeleted = false; //页面已离开：降级仅移出库
        } else {
        final goGrant = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要授权'),
            content: const Text(
              '删除本地文件需要"所有文件访问"权限。\n'
              '点击"去授权"后将跳转到系统设置，开启后返回本页会自动重试删除；\n'
              '若不想授权，可仅从 app 库中移除（本地文件保留）。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('仅移出库'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('去授权'),
              ),
            ],
          ),
        );
        if (goGrant == true && context.mounted) {
          //跳系统"特殊应用权限"页；返回后等待状态刷新再重试删除
          await Permission.manageExternalStorage.request();
          await Future<void>.delayed(const Duration(milliseconds: 600));
          if (await Permission.manageExternalStorage.isGranted) {
            if (await f.exists()) await f.delete();
          } else {
            fileDeleted = false; //用户未开启 → 降级仅移出库
          }
        } else {
          fileDeleted = false; //用户选择"仅移出库"
        }
        }
      } else {
        await f.delete();
      }
    }
  } catch (_) {
    fileDeleted = false;
  }
  //2. 歌曲库 + 独立收藏集
  await library.removeSongFromLibraryByPath(path);
  //3. 全部自定义歌单
  playlistProvider.removeSongFromAllPlaylists(path);
  //4. 播放队列任务（含"下一首"标记；正在播放的该歌播完自动切下一首）
  PlaylistService.instance.removeTaskByPath(path);
  //5. 权重记录（含基准）与周期衰减计数
  await WeightService.instance.removeSong(path);
  //6. 播放次数统计（永久删除才清；仅移除库保留）
  await PlaybackStatsService.instance.removePaths([path]);
  //7. 同步各服务库引用（播放源池过滤已删歌曲；播放器按路径找歌库同步）
  WeightService.instance.updateLibrary(library.songs);
  AudioPlaybackService.instance.updateLibrary(library.songs);
  PlaylistService.instance.updateLibrary(library.songs);
  if (!context.mounted) return;
  _showSnackBar(
    context,
    fileDeleted ? '已删除：${song.name}' : '未能删除本地文件，已仅从库中移除',
  );
}

//==================== 移除歌单（仅详情页） ====================

Future<void> _confirmRemoveFromPlaylist(
  BuildContext context,
  Song song,
  String? playlistId,
) async {
  if (playlistId == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('移除歌单'),
      content: Text('把「${song.name}」从这个歌单移除？（不会删除歌曲文件）'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('移除'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  context
      .read<PlaylistProvider>()
      .removeSongFromPlaylist(playlistId, song.audioFilePath);
  _showSnackBar(context, '已从歌单移除：${song.name}');
}

//==================== 工具 ====================

void _showSnackBar(BuildContext context, String message) {
  //浮层提示（root Overlay + 主题色）：避免被抽屉/BottomSheet 遮挡
  showAppNotice(context, message);
}

/// 毫秒 → m:ss
String _formatDuration(int ms) {
  final totalSeconds = (ms / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 字节 → 可读大小（B / KB / MB）
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

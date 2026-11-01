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
import '../services/weight_service.dart';

/// 多选底部操作条（v1.2）
///
/// 仅移除库 / 永久删除 / 加入歌单 / 添加下一首；按勾选顺序执行。
class SelectionActionBar extends StatefulWidget {
  const SelectionActionBar({
    super.key,
    required this.songs,
    required this.onFinished,
  });

  /// 按勾选顺序排列的歌曲
  final List<Song> songs;
  final VoidCallback onFinished;

  @override
  State<SelectionActionBar> createState() => _SelectionActionBarState();
}

class _SelectionActionBarState extends State<SelectionActionBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Material(
      color: color.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _btn(Icons.playlist_remove, '仅移除库', _onlyRemoveLibrary),
              _btn(Icons.delete_forever, '永久删除', _permanentlyDelete,
                  danger: true),
              _btn(Icons.playlist_add, '加入歌单', _addToPlaylist),
              _btn(Icons.playlist_play, '添加下一首', _addNext),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final c = danger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: _busy ? null : onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String content, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: action == '删除'
                  ? Theme.of(ctx).colorScheme.error
                  : null,
              foregroundColor: action == '删除' ? Colors.white : null,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onlyRemoveLibrary() async {
    final n = widget.songs.length;
    if (!await _confirm(
        '仅移除库',
        '将从 app 中移除选中的 $n 首歌曲（收藏/歌单/队列一并清理），'
            '但不会删除本地文件；下拉刷新后这些歌曲会重新出现。',
        '移除')) {
      return;
    }
    setState(() => _busy = true);
    if (!mounted) return;
    final library = context.read<LibraryProvider>();
    final playlists = context.read<PlaylistProvider>();
    //操作条会因选中歌曲被移除而先于本方法结束 dispose：
    //提前捕获 messenger/回调，后续不再使用本 State 的 context。
    final messenger = ScaffoldMessenger.of(context);
    final onFinished = widget.onFinished;
    final songs = widget.songs;
    for (final song in songs) {
      await library.removeSongFromLibraryByPath(song.audioFilePath);
      playlists.removeSongFromAllPlaylists(song.audioFilePath);
      PlaylistService.instance.removeTaskByPath(song.audioFilePath);
    }
    _syncServices(library);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已从 app 移除 $n 首歌曲（本地文件保留）')));
    onFinished();
  }

  Future<void> _permanentlyDelete() async {
    final n = widget.songs.length;
    if (!await _confirm(
        '永久删除',
        '将删除选中的 $n 首歌曲的本地文件，并从 app 中移除（不可恢复）。',
        '删除')) {
      return;
    }
    //Android 11+ 需"所有文件访问"；批量只询问一次
    var canDelete = true;
    if (Platform.isAndroid && !await Permission.manageExternalStorage.isGranted) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要授权'),
          content: const Text(
            '删除本地文件需要"所有文件访问"权限。\n'
            '前往系统设置开启后会自动继续；也可以仅从 app 移除（保留文件）。',
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
      if (go == true) {
        await Permission.manageExternalStorage.request();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        canDelete = await Permission.manageExternalStorage.isGranted;
      } else {
        canDelete = false;
      }
    }
    var failed = 0;
    if (canDelete) {
      for (final song in widget.songs) {
        try {
          final f = File(song.audioFilePath);
          if (await f.exists()) await f.delete();
        } catch (_) {
          failed++;
        }
      }
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final library = context.read<LibraryProvider>();
    final playlists = context.read<PlaylistProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final onFinished = widget.onFinished;
    final songs = widget.songs;
    for (final song in songs) {
      await library.removeSongFromLibraryByPath(song.audioFilePath);
      playlists.removeSongFromAllPlaylists(song.audioFilePath);
      PlaylistService.instance.removeTaskByPath(song.audioFilePath);
      if (canDelete) {
        await WeightService.instance.removeSong(song.audioFilePath);
      }
    }
    if (canDelete) {
      await PlaybackStatsService.instance
          .removePaths(songs.map((s) => s.audioFilePath));
    }
    _syncServices(library);
    final msg = !canDelete
        ? '未获得文件权限：已仅从 app 移除 $n 首歌曲（本地文件保留）'
        : (failed == 0
            ? '已永久删除 $n 首歌曲'
            : '已删除 ${n - failed} 首，$failed 首文件删除失败（已移出库）');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
    onFinished();
  }

  Future<void> _addToPlaylist() async {
    final provider = context.read<PlaylistProvider>();
    if (provider.playlists.isEmpty) {
      _snack('还没有自定义歌单，请先在抽屉中新建');
      return;
    }
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('加入歌单'),
        children: [
          for (final p in provider.playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p.id),
              child: Text('${p.name}（${p.songFilePaths.length} 首）'),
            ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final added = provider.addSongsToPlaylist(
        id, widget.songs.map((s) => s.audioFilePath).toList());
    if (!mounted) return;
    _snack(added > 0 ? '已加入 $added 首歌曲' : '所选歌曲都已在歌单中');
    widget.onFinished();
  }

  void _addNext() {
    for (final song in widget.songs) {
      PlaylistService.instance.addNextSong(song.audioFilePath);
      WeightService.instance.applyBehavior(song, WeightBehavior.addNext);
    }
    _snack('已按勾选顺序添加 ${widget.songs.length} 首到下一首');
    widget.onFinished();
  }

  void _syncServices(LibraryProvider library) {
    WeightService.instance.updateLibrary(library.songs);
    AudioPlaybackService.instance.updateLibrary(library.songs);
    PlaylistService.instance.updateLibrary(library.songs);
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_folder.dart';
import '../models/theme_palette.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/audio_playback_service.dart';
import '../services/playlist_service.dart';
import '../services/storage_service.dart';
import '../services/weight_service.dart';
import '../widgets/app_background.dart';

/// 所选文件夹管理（v1.1-5）
///
/// 入口：设置 → 播放 → 所选文件夹管理。
/// 展示用户通过抽屉"选择音乐文件夹"选过的文件夹；删除仅从 app 内移除
/// 该文件夹的歌曲（同步收藏/歌单/队列/权重），**不删除文件夹与音频文件**。
class MusicFoldersPage extends StatefulWidget {
  const MusicFoldersPage({super.key});

  @override
  State<MusicFoldersPage> createState() => _MusicFoldersPageState();
}

class _MusicFoldersPageState extends State<MusicFoldersPage> {
  List<MusicFolder> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await StorageService.loadMusicFolders();
    folders.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _loading = false;
    });
  }

  /// 该文件夹下当前库内歌曲数（用于确认弹窗提示）
  int _songCountOf(LibraryProvider library, String path) {
    final prefix = '${StorageService.normalizeFolderPath(path)}/';
    return library.songs
        .where((s) => s.audioFilePath.startsWith(prefix))
        .length;
  }

  Future<void> _confirmRemove(MusicFolder folder) async {
    final library = context.read<LibraryProvider>();
    final playlistProvider = context.read<PlaylistProvider>();
    final count = _songCountOf(library, folder.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除所选文件夹'),
        content: Text(
          '将从 app 中移除「${folder.name}」的 $count 首歌曲'
          '（同步收藏 / 歌单 / 播放队列 / 权重）。\n\n'
          '不会删除该文件夹，也不会删除其中的音频文件。\n\n'
          '确定移除吗？',
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
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    //1. 歌曲库 + 收藏（只移出库，不删文件）
    final removed = await library.removeSongsUnderFolder(folder.path);
    //2. 歌单 / 播放队列 / 权重联动
    for (final path in removed) {
      playlistProvider.removeSongFromAllPlaylists(path);
      PlaylistService.instance.removeTaskByPath(path);
      await WeightService.instance.removeSong(path);
    }
    //3. 同步各服务库引用（播放源队列过滤、播放器按路径找歌）
    WeightService.instance.updateLibrary(library.songs);
    AudioPlaybackService.instance.updateLibrary(library.songs);
    PlaylistService.instance.updateLibrary(library.songs);
    //4. 移除文件夹记录
    await StorageService.removeMusicFolder(folder.path);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已从 app 移除「${folder.name}」$count 首歌曲（本地文件保留）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Stack(
      children: [
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
          appBar: AppBar(title: const Text('所选文件夹管理'), centerTitle: true),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        '这里列出通过抽屉「选择音乐文件夹」添加过的文件夹。'
                        '移除只会从 app 内删除歌曲，不会删除文件夹或音频文件。',
                        style: TextStyle(color: secondary, fontSize: 12, height: 1.5),
                      ),
                    ),
                    if (_folders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                        child: Column(
                          children: [
                            Icon(Icons.folder_off_outlined,
                                size: 48, color: secondary),
                            const SizedBox(height: 12),
                            Text(
                              '还没有选择过音乐文件夹\n可在抽屉中点击「选择音乐文件夹」添加',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: secondary, height: 1.5),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final folder in _folders)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: Text(
                            '${folder.path}\n'
                            '${_songCountOf(context.watch<LibraryProvider>(), folder.path)} 首歌曲',
                            style: const TextStyle(fontSize: 12, height: 1.4),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: '从 app 移除该文件夹的歌曲',
                            icon: Icon(Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error),
                            onPressed: () => _confirmRemove(folder),
                          ),
                        ),
                  ],
                ),
        ),
      ],
    );
  }
}

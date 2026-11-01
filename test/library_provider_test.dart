import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/providers/library_provider.dart';
import 'package:fs_music_app/services/playlist_service.dart';
import 'package:fs_music_app/services/storage_service.dart';
import 'package:fs_music_app/services/weight_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LibraryProvider 删除歌曲联动测试（v1.1-2 需求 4 的库/收藏部分）：
/// mock path_provider 平台通道到临时目录 + SharedPreferences mock，
/// 验证 removeSongFromLibraryByPath 同步移除歌曲库与独立收藏集并落盘。
class _FakePathProvider extends PathProviderPlatform {
  final Directory dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_library_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
    WeightService.instance.resetForTest();
    PlaylistService.instance.resetForTest();
  });

  tearDown(() async {
    //不立即删除临时目录：StorageService 的写链上可能仍有本测试
    //unawaited 的写任务未执行完，提前删目录会触发"路径不存在"竞态
    //（目录残留由系统临时目录清理，测试环境可接受）
    // ignore: unused_local_variable
    final _ = tempDir;
  });

  Song makeSong(String path, {bool isFavorite = false}) {
    return Song(
      name: path.split('/').last.replaceAll('.mp3', ''),
      audioFilePath: path,
      sortNumber: 1,
      addTime: '2026-01-01T00:00:00.000',
      isFavorite: isFavorite,
    );
  }

  test('删除歌曲：歌曲库与独立收藏集同步移除并落盘', () async {
    //准备库：3 首歌，其中 a、b 已收藏（收藏集独立保存）
    await StorageService.saveSongs([
      makeSong('/path/a.mp3', isFavorite: true),
      makeSong('/path/b.mp3', isFavorite: true),
      makeSong('/path/c.mp3'),
    ]);
    await StorageService.saveFavoritePaths(['/path/a.mp3', '/path/b.mp3']);

    final provider = LibraryProvider();
    await provider.loadSongs();
    expect(provider.songs.length, 3);
    expect(provider.favoritePaths, ['/path/a.mp3', '/path/b.mp3']);

    //删除 b：库 + 收藏集都应移除（v1.2 默认添加时间倒序：c 在 a 前）
    await provider.removeSongFromLibraryByPath('/path/b.mp3');
    expect(provider.songs.map((s) => s.audioFilePath).toList(),
        ['/path/c.mp3', '/path/a.mp3']);
    expect(provider.favoritePaths, ['/path/a.mp3']);

    //落盘验证（重新读取磁盘文件）
    final songsOnDisk = await StorageService.loadSongs();
    expect(songsOnDisk.map((s) => s.audioFilePath),
        ['/path/c.mp3', '/path/a.mp3']);
    final favsOnDisk = await StorageService.loadFavoritePaths();
    expect(favsOnDisk, ['/path/a.mp3']);
  });

  test('删除不在库中的路径：静默不崩溃', () async {
    await StorageService.saveSongs([makeSong('/path/a.mp3')]);
    final provider = LibraryProvider();
    await provider.loadSongs();
    await provider.removeSongFromLibraryByPath('/path/none.mp3');
    expect(provider.songs.length, 1);
  });

  test('删除歌曲后排序编号连续（重排写库）', () async {
    //addTime 相同 → 次级 sortNumber 排序；删除中间歌后编号应重排为 1..n
    await StorageService.saveSongs([
      makeSong('/path/a.mp3', isFavorite: true),
      makeSong('/path/b.mp3'),
      makeSong('/path/c.mp3'),
    ]);
    final provider = LibraryProvider();
    await provider.loadSongs();
    await provider.removeSongFromLibraryByPath('/path/b.mp3');
    final disk = await StorageService.loadSongs();
    final numbers = disk.map((s) => s.sortNumber).toList();
    expect(numbers, [1, 2]);
  });

  test('移除所选文件夹：只移除该目录歌曲并同步收藏（不删文件）', () async {
    await StorageService.saveSongs([
      makeSong('/music/A/a1.mp3', isFavorite: true),
      makeSong('/music/A/a2.mp3'),
      makeSong('/music/B/b1.mp3', isFavorite: true),
    ]);
    await StorageService.saveFavoritePaths(
        ['/music/A/a1.mp3', '/music/B/b1.mp3']);

    final provider = LibraryProvider();
    await provider.loadSongs();
    final removed = await provider.removeSongsUnderFolder('/music/A/');
    expect(removed, ['/music/A/a1.mp3', '/music/A/a2.mp3']);
    expect(provider.songs.map((s) => s.audioFilePath), ['/music/B/b1.mp3']);
    expect(provider.favoritePaths, ['/music/B/b1.mp3']);

    final songsOnDisk = await StorageService.loadSongs();
    expect(songsOnDisk.map((s) => s.audioFilePath), ['/music/B/b1.mp3']);
    final favsOnDisk = await StorageService.loadFavoritePaths();
    expect(favsOnDisk, ['/music/B/b1.mp3']);
  });
}

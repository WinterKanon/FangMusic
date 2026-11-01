import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/play_task.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/models/song_weight_data.dart';
import 'package:fs_music_app/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// StorageService 数据安全测试（v1.1）：
/// mock path_provider 平台通道 → 在真实临时目录上验证
/// 原子写 / .bak 回退 / 收藏与权重独立持久化。
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_storage_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Song makeSong({
    String path = '/path/s1.mp3',
    double weight = 100.0,
    double baseWeight = 100.0,
    bool isFavorite = false,
  }) {
    return Song(
      name: 's1',
      audioFilePath: path,
      sortNumber: 1,
      addTime: '2026-01-01T00:00:00.000',
      weight: weight,
      baseWeight: baseWeight,
      isFavorite: isFavorite,
    );
  }

  File mainFile(String name) => File('${tempDir.path}/$name');

  /// 构造"主文件损坏 + .bak 有效"场景：主文件写坏内容，.bak 写有效 JSON
  Future<void> corruptMainWithValidBak(String name, String validJson) async {
    final f = mainFile(name);
    await f.writeAsString('this is not json {');
    await File('${f.path}.bak').writeAsString(validJson);
  }

  group('歌曲库：原子写 + .bak 自愈', () {
    test('saveSongs → loadSongs 往返（含 baseWeight 新字段）', () async {
      final songs = [
        makeSong(path: '/path/a.mp3', weight: 300, baseWeight: 60),
        makeSong(path: '/path/b.mp3', isFavorite: true),
      ];
      await StorageService.saveSongs(songs);
      final loaded = await StorageService.loadSongs();
      expect(loaded.length, 2);
      expect(loaded[0].weight, 300);
      expect(loaded[0].baseWeight, 60);
      expect(loaded[1].isFavorite, isTrue);
    });

    test('主文件损坏 → 回退 .bak，不返回空库', () async {
      final songs = [makeSong(path: '/path/a.mp3')];
      await StorageService.saveSongs(songs);
      //模拟写库中断后的现场：.bak 是上一次成功内容，主文件被写坏
      final f = mainFile('home_page_list_database.json');
      await File('${f.path}.bak').writeAsString(
        '{"songs":[{"name":"a","audioFilePath":"/path/a.mp3",'
        '"sortNumber":1,"addTime":"2026-01-01T00:00:00.000",'
        '"weight":100.0,"baseWeight":100.0}]}',
      );
      await f.writeAsString('broken{');
      final loaded = await StorageService.loadSongs();
      expect(loaded.length, 1);
      expect(loaded[0].audioFilePath, '/path/a.mp3');
    });

    test('主文件与 .bak 均损坏 → 返回空（不崩溃）', () async {
      await corruptMainWithValidBak(
        'home_page_list_database.json',
        'also broken {',
      );
      final loaded = await StorageService.loadSongs();
      expect(loaded, isEmpty);
    });
  });

  group('收藏集：独立持久化 + 自愈', () {
    test('saveFavoritePaths → loadFavoritePaths 往返', () async {
      await StorageService.saveFavoritePaths([
        '/path/a.mp3',
        '/path/b.mp3',
      ]);
      final paths = await StorageService.loadFavoritePaths();
      expect(paths, ['/path/a.mp3', '/path/b.mp3']);
    });

    test('主文件损坏 → 回退 .bak（收藏不丢）', () async {
      await StorageService.saveFavoritePaths(['/path/a.mp3']);
      final f = mainFile('favorite_database.json');
      await File('${f.path}.bak')
          .writeAsString('{"paths":["/path/a.mp3"]}');
      await f.writeAsString('broken{');
      final paths = await StorageService.loadFavoritePaths();
      expect(paths, ['/path/a.mp3']);
    });
  });

  group('权重库：独立持久化 + 自愈', () {
    test('saveWeights → loadWeights 往返（weight + baseWeight）', () async {
      await StorageService.saveWeights({
        '/path/a.mp3': const SongWeightData(
          weight: 130,
          baseWeight: 60,
          lastWeightIncreaseTime: '2026-10-01T00:00:00.000',
        ),
        '/path/b.mp3': const SongWeightData(weight: 100),
      });
      final weights = await StorageService.loadWeights();
      expect(weights.length, 2);
      expect(weights['/path/a.mp3']!.weight, 130);
      expect(weights['/path/a.mp3']!.baseWeight, 60);
      expect(weights['/path/b.mp3']!.baseWeight, 100); //缺省基准
    });

    test('主文件损坏 → 回退 .bak（权重不丢）', () async {
      await StorageService.saveWeights({
        '/path/a.mp3': const SongWeightData(weight: 250),
      });
      final f = mainFile('weight_database.json');
      await File('${f.path}.bak').writeAsString(
        '{"weights":{"/path/a.mp3":{"weight":250.0,"baseWeight":100.0}}}',
      );
      await f.writeAsString('broken{');
      final weights = await StorageService.loadWeights();
      expect(weights['/path/a.mp3']!.weight, 250);
    });
  });

  group('所选文件夹（v1.1-5）', () {
    test('添加去重 / 末尾斜杠规范化 / 移除', () async {
      await StorageService.addMusicFolder('/storage/emulated/0/Music/A/');
      await StorageService.addMusicFolder('/storage/emulated/0/Music/A');
      await StorageService.addMusicFolder('/storage/emulated/0/Music/B');
      final folders = await StorageService.loadMusicFolders();
      expect(folders.length, 2);
      expect(folders[0].path, '/storage/emulated/0/Music/A');
      expect(folders[0].name, 'A');
      await StorageService.removeMusicFolder('/storage/emulated/0/Music/A');
      final after = await StorageService.loadMusicFolders();
      expect(after.length, 1);
      expect(after.single.path, '/storage/emulated/0/Music/B');
    });

    test('旧歌曲库补录文件夹：按目录补录且重复调用不重复', () async {
      final songs = [
        makeSong(path: '/music/A/s1.mp3'),
        makeSong(path: '/music/A/s2.mp3'),
        makeSong(path: '/music/B/s3.mp3'),
      ];
      await StorageService.ensureFoldersForSongs(songs);
      var folders = await StorageService.loadMusicFolders();
      expect(folders.length, 2);
      expect(folders.map((f) => f.path), containsAll(['/music/A', '/music/B']));
      await StorageService.ensureFoldersForSongs(songs);
      folders = await StorageService.loadMusicFolders();
      expect(folders.length, 2);
    });
  });

  group('播放队列 / 歌单：.bak 回退加固（v1.1）', () {
    test('播放队列主文件损坏 → 回退 .bak', () async {
      await StorageService.savePlayTasks([
        PlayTask(songFilePath: '/path/a.mp3', isNextSong: true),
        PlayTask(songFilePath: '/path/b.mp3'),
      ]);
      final f = mainFile('home_play_task_database.json');
      await File('${f.path}.bak').writeAsString(
        '{"tasks":[{"songFilePath":"/path/a.mp3","isNextSong":true},'
        '{"songFilePath":"/path/b.mp3"}]}',
      );
      await f.writeAsString('broken{');
      final tasks = await StorageService.loadPlayTasks();
      expect(tasks.length, 2);
      expect(tasks[0].songFilePath, '/path/a.mp3');
      expect(tasks[0].isNextSong, isTrue);
    });

    test('歌单主文件损坏 → 回退 .bak（空歌单也回退，不误判为空）', () async {
      await StorageService.savePlaylists([]);
      final f = mainFile('playlist_database.json');
      await File('${f.path}.bak').writeAsString('{"playlists":[]}');
      await f.writeAsString('broken{');
      final playlists = await StorageService.loadPlaylists();
      expect(playlists, isEmpty);
    });

    test('原始 JSON 读取：损坏文件返回 null（调试页不崩）', () async {
      final f = mainFile('home_page_list_database.json');
      await f.writeAsString('broken{');
      expect(await StorageService.readSongsRaw(), 'broken{');
    });
  });
}

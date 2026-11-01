import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/playlist.dart';
import 'package:fs_music_app/models/play_mode.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/providers/playlist_provider.dart';
import 'package:fs_music_app/services/playlist_service.dart';
import 'package:fs_music_app/services/weight_service.dart';

/// v1.0 第三阶段（歌单）测试：
/// - Playlist 模型：序列化往返 + 歌单名规则校验
/// - PlaylistProvider：CRUD + 幂等 + 状态广播（纯内存，持久化在测试环境
///   无平台通道时被 catch 兜住，与 v0.0/主题测试模式一致）
/// - PlaylistService 播放源：allSongs / favorites（动态过滤）/ playlist（歌单池）：
///   切源重建队列、歌单删除回退、随机批次只在源池内采样
void main() {
  /// 构造 n 首歌的库（sortNumber 1..n，可指定收藏标记）
  List<Song> makeLibrary(int n, {Set<int> favorites = const {}}) {
    return List.generate(
      n,
      (i) => Song(
        name: 'song${i + 1}',
        audioFilePath: '/path/song${i + 1}.mp3',
        sortNumber: i + 1,
        addTime: DateTime(2026, 1, 1).toIso8601String(),
        isFavorite: favorites.contains(i + 1),
      ),
    );
  }

  Playlist makePlaylist(String id, String name, List<String> paths) {
    return Playlist(
      id: id,
      name: name,
      createTime: DateTime(2026, 1, 1).toIso8601String(),
      songFilePaths: paths,
    );
  }

  group('Playlist 模型', () {
    test('JSON 往返：字段完整保留', () {
      final p = makePlaylist('pl_1', '我的歌单', ['/a.mp3', '/b.mp3']);
      final back = Playlist.fromJson(p.toJson());
      expect(back.id, 'pl_1');
      expect(back.name, '我的歌单');
      expect(back.songFilePaths, ['/a.mp3', '/b.mp3']);
      expect(back.createTime, p.createTime);
    });

    test('空歌单往返：songFilePaths 为空列表', () {
      final p = makePlaylist('pl_2', '空歌单', const []);
      final back = Playlist.fromJson(p.toJson());
      expect(back.songFilePaths, isEmpty);
    });

    test('歌单名规则：非空 / ≤20 字 / 不含非法字符', () {
      expect(Playlist.validateName(''), isNotNull); //空
      expect(Playlist.validateName('   '), isNotNull); //纯空格
      expect(Playlist.validateName('a' * 21), isNotNull); //超 20 字
      for (final c in ['\\', '/', ':', '*', '?', '"', '<', '>', '|']) {
        expect(Playlist.validateName('ab$c'), isNotNull, reason: '非法字符 $c');
      }
      //合法名
      expect(Playlist.validateName('我的歌单'), isNull);
      expect(Playlist.validateName('a' * 20), isNull); //正好 20 字
      expect(Playlist.validateName(' 摇滚 2026 '), isNull); //首尾空格 trim 后合法
    });
  });

  group('PlaylistProvider CRUD', () {
    late PlaylistProvider provider;
    setUp(() {
      provider = PlaylistProvider();
      provider.resetForTest();
    });

    test('创建歌单：追加到末尾，名字 trim', () {
      final p = provider.createPlaylist('  周末开车  ');
      expect(p.name, '周末开车');
      expect(provider.playlists.length, 1);
      expect(provider.playlistById(p.id)?.name, '周末开车');
    });

    test('重命名：按 id 生效；找不到 id 忽略', () {
      final p = provider.createPlaylist('旧名');
      provider.renamePlaylist(p.id, '新名');
      expect(provider.playlistById(p.id)?.name, '新名');
      provider.renamePlaylist('pl_not_exist', 'x'); //不存在的 id
      expect(provider.playlists.length, 1);
      expect(provider.playlistById(p.id)?.name, '新名');
    });

    test('删除：按 id 移除', () {
      final p1 = provider.createPlaylist('一');
      final p2 = provider.createPlaylist('二');
      provider.deletePlaylist(p1.id);
      expect(provider.playlists.length, 1);
      expect(provider.playlistById(p1.id), isNull);
      expect(provider.playlistById(p2.id)?.name, '二');
      provider.deletePlaylist('pl_not_exist'); //不存在的 id
      expect(provider.playlists.length, 1);
    });

    test('加歌：幂等（已在歌单中不加重复）；歌单不存在忽略', () {
      final p = provider.createPlaylist('歌单');
      expect(provider.addSongToPlaylist(p.id, '/a.mp3'), isTrue);
      expect(provider.addSongToPlaylist(p.id, '/b.mp3'), isTrue);
      expect(provider.addSongToPlaylist(p.id, '/a.mp3'), isFalse); //重复
      expect(provider.playlistById(p.id)?.songFilePaths, ['/a.mp3', '/b.mp3']);
      expect(provider.addSongToPlaylist('pl_not_exist', '/c.mp3'), isFalse);
    });

    test('移歌：幂等；歌单不存在忽略', () {
      final p = provider.createPlaylist('歌单');
      provider.addSongToPlaylist(p.id, '/a.mp3');
      provider.addSongToPlaylist(p.id, '/b.mp3');
      expect(provider.removeSongFromPlaylist(p.id, '/a.mp3'), isTrue);
      expect(provider.removeSongFromPlaylist(p.id, '/a.mp3'), isFalse); //已不在
      expect(provider.playlistById(p.id)?.songFilePaths, ['/b.mp3']);
      expect(provider.removeSongFromPlaylist('pl_not_exist', '/b.mp3'), isFalse);
    });

    test('歌单名 trim 后保存（重命名/创建都 trim）', () {
      final p = provider.createPlaylist(' 名字  ');
      expect(p.name, '名字');
      provider.renamePlaylist(p.id, '  新名  ');
      expect(provider.playlistById(p.id)?.name, '新名');
    });
  });

  group('PlaylistService 播放源', () {
    final service = PlaylistService.instance;

    setUp(() {
      WeightService.instance.resetForTest();
      service.resetForTest();
    });

    test('playlist 源：顺序模式队列 = 歌单内添加顺序', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song3.mp3', '/path/song1.mp3', '/path/song2.mp3']),
      ]);
      service.updateLibrary(makeLibrary(5));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.source, PlaySource.playlist);
      expect(service.sourcePlaylistId, 'pl_1');
      expect(service.length, 3);
      expect(service.tasks[0].songFilePath, '/path/song3.mp3');
      expect(service.tasks[1].songFilePath, '/path/song1.mp3');
      expect(service.tasks[2].songFilePath, '/path/song2.mp3');
      expect(service.currentIndex, 0);
    });

    test('playlist 源：歌单中的歌不在库中时过滤掉', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song9.mp3', '/path/song1.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      //song9 不在库中 → 只保留 song1
      expect(service.length, 1);
      expect(service.tasks.first.songFilePath, '/path/song1.mp3');
    });

    test('favorites 源：池 = isFavorite 动态过滤；收藏变化后 updateLibrary 同步', () async {
      service.updateLibrary(makeLibrary(4, favorites: {1, 3}));
      await service.setPlaySource(PlaySource.favorites);
      expect(service.source, PlaySource.favorites);
      expect(service.length, 2);
      expect(service.tasks.map((t) => t.songFilePath).toSet(),
          {'/path/song1.mp3', '/path/song3.mp3'});

      //收藏 song2（模拟 LibraryProvider.toggleFavorite 后 updateLibrary）
      final songs2 = [
        for (final s in makeLibrary(4, favorites: {1, 3}))
          s.audioFilePath == '/path/song2.mp3' ? s.copyWith(isFavorite: true) : s,
      ];
      service.updateLibrary(songs2);
      expect(service.length, 3);
      expect(
        service.tasks.map((t) => t.songFilePath).toSet(),
        {'/path/song1.mp3', '/path/song2.mp3', '/path/song3.mp3'},
      );
    });

    test('切回 allSongs：池恢复全库顺序', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song3.mp3', '/path/song1.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.length, 2);
      await service.setPlaySource(PlaySource.allSongs);
      expect(service.source, PlaySource.allSongs);
      expect(service.length, 3);
      expect(service.tasks.first.songFilePath, '/path/song1.mp3');
    });

    test('相同源重复切换忽略（不重建）；playlist 同 id 忽略', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song3.mp3', '/path/song1.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      final tasksBefore = service.tasks.map((t) => t.songFilePath).toList();
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.tasks.map((t) => t.songFilePath).toList(), tasksBefore);
    });

    test('当前播放源歌单被删除 → updatePlaylists 回退 allSongs', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song3.mp3', '/path/song1.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.source, PlaySource.playlist);

      //模拟抽屉删除歌单后 PlaylistProvider 通知服务
      service.updatePlaylists(const []);
      expect(service.source, PlaySource.allSongs);
      expect(service.length, 3); //已重建为全库
    });

    test('playlist 源随机模式：批次全部来自歌单池', () async {
      service.resetForTest(mode: PlayMode.realRandom);
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song1.mp3', '/path/song3.mp3']),
      ]);
      service.updateLibrary(makeLibrary(5));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.length, 50); //2 首歌 → 50 首批次（允许连播）
      final pool = {'/path/song1.mp3', '/path/song3.mp3'};
      for (final t in service.tasks) {
        expect(pool.contains(t.songFilePath), isTrue,
            reason: '随机批次只能在歌单池内采样');
      }
    });

    test('切源时保留当前播放歌（keepSongId）：歌在新池中作 #1', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song2.mp3', '/path/song1.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      service.rebuildQueue(); //allSongs：song1,song2,song3
      service.moveToIndex(1); //当前 = song2
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      //song2 在歌单池中 → 保留为 #1
      expect(service.tasks.first.songFilePath, '/path/song2.mp3');
      expect(service.currentIndex, 0);
    });

    test('切源时当前歌不在新池：不保留，从新池队首开始', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song2.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      service.rebuildQueue(); //allSongs：song1,song2,song3
      service.moveToIndex(0); //当前 = song1（不在歌单池）
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.length, 1);
      expect(service.tasks.first.songFilePath, '/path/song2.mp3');
      expect(service.currentIndex, 0);
    });

    test('歌单内加歌后 updatePlaylists 同步：队列包含新歌', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song1.mp3']),
      ]);
      service.updateLibrary(makeLibrary(3));
      service.rebuildQueue(); //allSongs
      //切到歌单源
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      expect(service.length, 1);
      //歌单加入 song3（模拟长按"加入歌单…"后 Provider 变更 → 服务同步）
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song1.mp3', '/path/song3.mp3']),
      ]);
      expect(service.length, 2);
      expect(service.tasks.last.songFilePath, '/path/song3.mp3');
    });

    test('歌单源 + 顺序模式：点歌播放后，播完自动连播歌单内下一首', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单',
            ['/path/song1.mp3', '/path/song2.mp3', '/path/song3.mp3']),
      ]);
      service.updateLibrary(makeLibrary(5));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      //详情页点歌 song2（moveTo 定位）
      service.moveTo('/path/song2.mp3');
      expect(service.taskAt(service.currentIndex)?.songFilePath,
          '/path/song2.mp3');
      //播完 → 自动连播：应返回歌单内 song2 的下一首 song3
      final next = service.nextTask();
      expect(next?.songFilePath, '/path/song3.mp3');
      expect(service.taskAt(service.currentIndex)?.songFilePath,
          '/path/song3.mp3');
    });

    test('歌单源 + 顺序模式：播完最后一首回到队首继续', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song1.mp3', '/path/song2.mp3']),
      ]);
      service.updateLibrary(makeLibrary(5));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      service.moveTo('/path/song2.mp3'); //最后一首
      final next = service.nextTask();
      expect(next?.songFilePath, '/path/song1.mp3'); //回队首
      expect(service.currentIndex, 0);
    });

    test('歌单源 + 顺序模式：当前歌不在队列（极端）时 nextTask 从队首返回', () async {
      service.updatePlaylists([
        makePlaylist('pl_1', '歌单', ['/path/song1.mp3', '/path/song2.mp3']),
      ]);
      service.updateLibrary(makeLibrary(5));
      await service.setPlaySource(PlaySource.playlist, playlistId: 'pl_1');
      //直接令 currentIndex 指向不存在的位置（越界保护）
      service.moveToIndex(0);
      service.moveToIndex(5); //越界被忽略
      final next = service.nextTask();
      expect(next, isNotNull);
      expect(service.currentIndex, 1);
    });
  });
}

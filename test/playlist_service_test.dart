import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/play_mode.dart';
import 'package:fs_music_app/models/playlist.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/services/playlist_service.dart';
import 'package:fs_music_app/services/weight_service.dart';

/// 播放队列服务核心逻辑测试（纯内存，不碰磁盘/平台通道）
void main() {
  final service = PlaylistService.instance;

  /// 构造 n 首歌的库（sortNumber 1..n）
  List<Song> makeLibrary(int n) {
    return List.generate(
      n,
      (i) => Song(
        name: 'song${i + 1}',
        audioFilePath: '/path/song${i + 1}.mp3',
        sortNumber: i + 1,
        addTime: DateTime(2026, 1, 1).toIso8601String(),
      ),
    );
  }

  group('收藏源顺序（v1.2）', () {
    test('favorites 源按收藏顺序生成队列，而非库顺序', () {
      service.resetForTest(source: PlaySource.favorites);
      service.updateFavoriteOrder(['/path/song3.mp3', '/path/song1.mp3']);
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      expect(service.tasks.map((t) => t.songFilePath).toList(),
          ['/path/song3.mp3', '/path/song1.mp3']);
    });
  });

  group('手动点歌重排（v1.2）', () {
    setUp(() => service.resetForTest());

    test('以点击歌为首，下一首任务紧随其后，其余歌曲环绕', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue(); //1..5
      service.addNextSong('/path/song5.mp3');
      service.rebuildQueueStartingAt('/path/song3.mp3');
      expect(service.tasks.map((t) => t.songFilePath).toList(), [
        '/path/song3.mp3',
        '/path/song5.mp3',
        '/path/song4.mp3',
        '/path/song5.mp3',
        '/path/song1.mp3',
        '/path/song2.mp3',
      ]);
      expect(service.tasks[1].isNextSong, isTrue);
      expect(service.currentIndex, 0);
    });
  });

  group('列表排序同步（v1.2 applyListOrder）', () {
    setUp(() => service.resetForTest());

    test('顺序模式：按新顺序重排，保留当前歌与“下一首”标记', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue(); //1..5
      service.moveToIndex(1); //当前 song2
      service.addNextSong('/path/song5.mp3'); //song5 标记下一首
      service.applyListOrder(
        ['/path/song5.mp3', '/path/song4.mp3', '/path/song3.mp3',
          '/path/song2.mp3', '/path/song1.mp3'],
        keepSongId: '/path/song2.mp3',
      );
      //基础逆序为 5,4,3,2,1；当前 song2 在索引 3，下一首标记 song5 插到其后
      expect(service.tasks.map((t) => t.songFilePath).toList(), [
        '/path/song5.mp3',
        '/path/song4.mp3',
        '/path/song3.mp3',
        '/path/song2.mp3',
        '/path/song5.mp3',
        '/path/song1.mp3',
      ]);
      expect(service.tasks[4].isNextSong, isTrue);
      expect(service.currentIndex, 3);
      expect(service.tasks[3].songFilePath, '/path/song2.mp3');
    });

    test('随机模式：applyListOrder 不改队列', () {
      service.resetForTest(mode: PlayMode.realRandom);
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(1);
      final before = service.tasks.map((t) => t.songFilePath).toList();
      service.applyListOrder(['/path/song5.mp3', '/path/song1.mp3']);
      expect(service.tasks.map((t) => t.songFilePath).toList(), before);
    });
  });

  group('顺序模式队列', () {
    setUp(() => service.resetForTest());

    test('按 sortNumber 全库生成，当前索引在队首', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      expect(service.length, 5);
      expect(service.tasks.first.songFilePath, '/path/song1.mp3');
      expect(service.tasks.last.songFilePath, '/path/song5.mp3');
      expect(service.currentIndex, 0);
    });

    test('边界：最后一首的下一首回到第一首', () {
      service.updateLibrary(makeLibrary(3));
      service.rebuildQueue();
      service.moveToIndex(2);
      final next = service.nextTask();
      expect(next!.songFilePath, '/path/song1.mp3');
      expect(service.currentIndex, 0);
    });

    test('上一首：队首的上一首回到最后一首', () {
      service.updateLibrary(makeLibrary(3));
      service.rebuildQueue();
      final prev = service.previousTask();
      expect(prev!.songFilePath, '/path/song3.mp3');
      expect(service.currentIndex, 2);
    });
  });

  group('添加下一首', () {
    setUp(() => service.resetForTest());

    test('插到当前歌之后（已有"下一首"任务之后）', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue(); //song1..song5
      service.moveToIndex(1); //当前 = song2
      service.addNextSong('/path/song5.mp3');
      service.addNextSong('/path/song4.mp3');
      //期望：song1, song2, [song5, song4](下一首), song3, song4, song5
      expect(service.tasks[1].songFilePath, '/path/song2.mp3');
      expect(service.tasks[2].isNextSong, isTrue);
      expect(service.tasks[2].songFilePath, '/path/song5.mp3');
      expect(service.tasks[3].isNextSong, isTrue);
      expect(service.tasks[3].songFilePath, '/path/song4.mp3');
      expect(service.tasks[4].isNextSong, isFalse); //后续任务顺延
    });

    test('队列为空（未定位播放）时插入队首', () {
      service.updateLibrary(makeLibrary(3));
      //不 rebuildQueue：currentIndex 保持 -1，模拟从未播放
      service.addNextSong('/path/song9.mp3');
      expect(service.tasks.first.songFilePath, '/path/song9.mp3');
      expect(service.tasks.first.isNextSong, isTrue);
    });
  });

  group('普通随机批次', () {
    setUp(() => service.resetForTest(mode: PlayMode.realRandom));

    test('批次 50 首，同歌最多连续 2 次', () {
      service.updateLibrary(makeLibrary(4));
      service.rebuildQueue();
      expect(service.length, 50);
      for (var i = 2; i < service.tasks.length; i++) {
        final sameAsPrev2 =
            service.tasks[i].songFilePath ==
                service.tasks[i - 1].songFilePath &&
            service.tasks[i].songFilePath ==
                service.tasks[i - 2].songFilePath;
        expect(sameAsPrev2, isFalse, reason: '不允许连续 3 次同一首歌');
      }
    });

    test('循环边界重排：生成新批次，不强制当前歌作 #1', () {
      service.updateLibrary(makeLibrary(4));
      service.rebuildQueue();
      final before = service.tasks.map((t) => t.songFilePath).toList();
      service.moveToIndex(service.length - 1); //当前 = 队列最后一首
      final next = service.nextTask();
      expect(next, isNotNull);
      expect(service.currentIndex, 0);
      expect(service.length, 50); //新批次仍是 50 首
      expect(service.tasks.map((t) => t.songFilePath).toList(),
          isNot(equals(before))); //队列已重排（内容/顺序变化）
    });

    test('边界重排保留未播放的"下一首"任务（含当前歌之前的）', () {
      service.updateLibrary(makeLibrary(10));
      service.rebuildQueue();
      //在队首后添加两首"下一首"
      service.moveToIndex(0);
      final p1 = service.tasks[5].songFilePath;
      final p2 = service.tasks[8].songFilePath;
      service.addNextSong(p1);
      service.addNextSong(p2); //插到 index 1、2（isNextSong）
      //用户跳到队列最后一首（第 50+2 首）再点"下一首" → 边界重排
      service.moveToIndex(service.length - 1);
      service.nextTask();
      final flags = service.tasks.where((t) => t.isNextSong).toList();
      expect(flags.length, 2); //未播放的"下一首"任务被保留
      expect(flags[0].songFilePath, p1);
      expect(flags[1].songFilePath, p2);
    });

    test('滑动窗口：距末尾 ≤10 时补一批（不超过上限 1000）', () {
      service.updateLibrary(makeLibrary(4));
      service.rebuildQueue();
      //推进到距末尾 ≤10，触发 refill
      for (var i = 0; i < 40; i++) {
        service.nextTask();
      }
      expect(service.length, greaterThan(50));
      expect(service.length, lessThanOrEqualTo(1000));
    });
  });

  group('模式切换', () {
    setUp(() => service.resetForTest(mode: PlayMode.realRandom));

    test('随机 → 单曲循环：保留切换前的队列排列与当前位置', () {
      service.updateLibrary(makeLibrary(4));
      service.rebuildQueue();
      final before = service.tasks.map((t) => t.songFilePath).toList();
      service.moveToIndex(2);
      final curBefore = service.currentIndex;
      service.setMode(PlayMode.repeatOne);
      expect(service.mode, PlayMode.repeatOne);
      expect(service.tasks.map((t) => t.songFilePath).toList(), before);
      expect(service.currentIndex, curBefore);
    });

    test('顺序 → 单曲循环：保留排列（sortNumber 全库不变）', () {
      service.resetForTest(); //顺序模式
      service.updateLibrary(makeLibrary(4));
      service.rebuildQueue();
      final before = service.tasks.map((t) => t.songFilePath).toList();
      service.setMode(PlayMode.repeatOne);
      expect(service.mode, PlayMode.repeatOne);
      expect(service.tasks.map((t) => t.songFilePath).toList(), before);
    });
  });

  group('下一首标记消费', () {
    setUp(() => service.resetForTest());

    test('任务被播放后清除"下一首"标记', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue(); //song1..song5，当前 = song1
      service.addNextSong('/path/song9.mp3'); //插到 song1 之后
      expect(service.tasks[1].isNextSong, isTrue);
      final next = service.nextTask(); //播放到 song9
      expect(next!.songFilePath, '/path/song9.mp3');
      expect(service.tasks[1].isNextSong, isFalse); //标记已消费清除
      expect(service.tasks[1].songFilePath, '/path/song9.mp3'); //仍是队列成员
    });

    test('队列页点击播放"下一首"任务后清除标记', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.addNextSong('/path/song9.mp3');
      expect(service.tasks[1].isNextSong, isTrue);
      service.moveToIndex(1); //点击播放它
      expect(service.tasks[1].isNextSong, isFalse);
    });
  });

  group('随机模式手动点歌', () {
    setUp(() => service.resetForTest(mode: PlayMode.realRandom));

    test('点击"在库但不在队列"的歌：重排批次，点击的歌排 #1，下一首不重复', () {
      service.updateLibrary(makeLibrary(60));
      service.rebuildQueue(); //随机 50 首（60 首库 → 有歌不在批次中）
      //找一首不在队列中的歌
      final inQueue = service.tasks.map((t) => t.songFilePath).toSet();
      String? outside;
      for (var i = 1; i <= 60; i++) {
        final p = '/path/song$i.mp3';
        if (!inQueue.contains(p)) {
          outside = p;
          break;
        }
      }
      expect(outside, isNotNull);
      service.moveTo(outside!);
      expect(service.tasks.first.songFilePath, outside); //排 #1
      expect(service.currentIndex, 0);
      expect(service.length, 50); //重排后仍 50 首
      final next = service.nextTask();
      expect(next!.songFilePath, isNot(outside)); //下一首不重复当前歌
      expect(service.currentIndex, 1);
    });

    test('点击已在队列的歌：同样重排并排 #1', () {
      service.updateLibrary(makeLibrary(10));
      service.rebuildQueue(); //50 首（10 首库重复）
      final target = service.tasks[5].songFilePath;
      service.moveTo(target);
      expect(service.tasks.first.songFilePath, target);
      expect(service.currentIndex, 0);
    });

    test('重排后保留"下一首"任务（插到当前歌之后）', () {
      service.updateLibrary(makeLibrary(10));
      service.rebuildQueue();
      service.moveTo(service.tasks[3].songFilePath); //当前 = tasks[3]
      final target = service.tasks[0].songFilePath;
      //选一首与 target 不同的歌作为"下一首"任务
      String nextPath = '';
      for (final t in service.tasks) {
        if (t.songFilePath != target) {
          nextPath = t.songFilePath;
          break;
        }
      }
      expect(nextPath, isNotEmpty);
      service.addNextSong(nextPath);
      service.moveTo(target); //再点击另一首 → 重排，target 排 #1
      expect(service.tasks.first.songFilePath, target);
      expect(service.tasks[1].isNextSong, isTrue); //"下一首"任务保留在 #1 之后
      expect(service.tasks[1].songFilePath, nextPath);
    });
  });

  group('加权随机批次（CDF 采样）', () {
    setUp(() {
      service.resetForTest(mode: PlayMode.weightedRandom);
      WeightService.instance.resetForTest();
    });

    /// 构造带权重的库并同步给两个服务
    void setupWeightedLibrary(List<double> weights) {
      final songs = [
        for (var i = 0; i < weights.length; i++)
          Song(
            name: 'song${i + 1}',
            audioFilePath: '/path/song${i + 1}.mp3',
            sortNumber: i + 1,
            addTime: DateTime(2026, 1, 1).toIso8601String(),
            weight: weights[i],
          ),
      ];
      service.updateLibrary(songs);
      WeightService.instance.updateLibrary(songs);
    }

    test('高权重歌出现频率显著更高（统计 50 首批次）', () {
      //两首歌权重 100 : 300（期望 1:3）
      setupWeightedLibrary([100, 300]);
      service.rebuildQueue();
      expect(service.length, 50);
      final bCount =
          service.tasks.where((t) => t.songFilePath == '/path/song2.mp3').length;
      //期望约 37.5 首；宽松区间 [20, 49] 几乎不可能 flaky
      expect(bCount, greaterThan(20));
      expect(bCount, lessThanOrEqualTo(49));
    });

    test('keepSongId 排 #1，且保持 50 首批次', () {
      setupWeightedLibrary([100, 300, 200]);
      service.rebuildQueue(keepSongId: '/path/song3.mp3');
      expect(service.tasks.first.songFilePath, '/path/song3.mp3');
      expect(service.currentIndex, 0);
      expect(service.length, 50);
    });

    test('同歌最多连续 2 次（加权采样也遵守）', () {
      setupWeightedLibrary([100, 300]);
      service.rebuildQueue();
      for (var i = 2; i < service.tasks.length; i++) {
        final sameAsPrev2 =
            service.tasks[i].songFilePath ==
                service.tasks[i - 1].songFilePath &&
            service.tasks[i].songFilePath ==
                service.tasks[i - 2].songFilePath;
        expect(sameAsPrev2, isFalse, reason: '不允许连续 3 次同一首歌');
      }
    });

    test('循环边界重排：生成新批次，保留"下一首"任务', () {
      setupWeightedLibrary([100, 300, 200, 150]);
      service.rebuildQueue();
      service.moveToIndex(0);
      final p1 = service.tasks[5].songFilePath;
      final p2 = service.tasks[8].songFilePath;
      service.addNextSong(p1);
      service.addNextSong(p2);
      service.moveToIndex(service.length - 1);
      final next = service.nextTask();
      expect(next, isNotNull);
      expect(service.currentIndex, 0);
      // 50 首批次 + 2 首保留的"下一首"任务（插到队首之后）
      expect(service.length, 52);
      final flags = service.tasks.where((t) => t.isNextSong).toList();
      expect(flags.length, 2); //未播放的"下一首"任务保留
      expect(flags[0].songFilePath, p1);
      expect(flags[1].songFilePath, p2);
    });

    test('主页点歌重排：点击的歌排 #1（加权模式）', () {
      setupWeightedLibrary([100, 300, 200, 150, 80]);
      service.rebuildQueue();
      final target = service.tasks[10].songFilePath;
      service.moveTo(target);
      expect(service.tasks.first.songFilePath, target);
      expect(service.currentIndex, 0);
    });
  });
  group('移除任务（v1.1-2：队列减号 + 删除歌曲联动）', () {
    setUp(() => service.resetForTest());

    test('removeTaskAt 移除当前播放之前的任务 → 当前索引同步前移', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(2); //当前 = song3
      service.removeTaskAt(0); //移除 song1（当前之前）
      expect(service.length, 4);
      expect(service.currentIndex, 1); //song3 前移到位置 1
      expect(service.taskAt(1)!.songFilePath, '/path/song3.mp3');
    });

    test('removeTaskAt 移除正在播放的任务 → 播完自动切下一首（不重播前一首）', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(1); //当前 = song2
      service.removeTaskAt(1);
      expect(service.length, 4);
      expect(service.currentIndex, 0); //回退一位
      final next = service.nextTask();
      expect(next!.songFilePath, '/path/song3.mp3'); //跳过已播过的 song1
    });

    test('removeTaskAt 队首正在播放被移除 → -1，nextTask 重置队首', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(0); //当前 = song1
      service.removeTaskAt(0);
      expect(service.currentIndex, -1);
      expect(service.nextTask()!.songFilePath, '/path/song2.mp3');
    });

    test('removeTaskByPath 移除该歌全部任务（含"下一首"标记）', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(0);
      service.addNextSong('/path/song3.mp3'); //song3 在队列尾部再加一个
      expect(service.length, 6);
      service.removeTaskByPath('/path/song3.mp3');
      expect(service.length, 4);
      expect(service.tasks.where((t) => t.songFilePath == '/path/song3.mp3'),
          isEmpty);
    });

    test('removeTaskByPath 正在播放被删 → 播完切下一首（当前之前的歌不重播）', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(2); //当前 = song3
      service.removeTaskByPath('/path/song3.mp3');
      expect(service.length, 4);
      final next = service.nextTask();
      expect(next!.songFilePath, '/path/song4.mp3');
    });

    test('removeTaskByPath 当前位置前后的副本都删 → 索引按前移数量修正', () {
      service.updateLibrary(makeLibrary(5));
      service.rebuildQueue();
      service.moveToIndex(3); //当前 = song4（队列 song1..song5）
      service.addNextSong('/path/song1.mp3'); //插到 song4 之后（"下一首"）
      //队列：song1,song2,song3,song4,song1,song5；当前位置 3
      service.removeTaskByPath('/path/song1.mp3');
      //删 2 个 song1：1 个在当前位置之前（队首）→ 索引前移 1
      expect(service.length, 4);
      expect(service.currentIndex, 2); //song4 前移到位置 2
      final next = service.nextTask();
      expect(next!.songFilePath, '/path/song5.mp3');
    });

    test('removeTaskAt/removeTaskByPath 触发 onTaskRemoved 回调（播放器池同步）', () {
      final removed = <int>[];
      PlaylistService.onTaskRemoved = (at, path) => removed.add(at);
      try {
        service.updateLibrary(makeLibrary(5));
        service.rebuildQueue(); //song1..song5
        service.removeTaskAt(2); //song3 → 回调位置 2
        expect(removed, [2]);
        removed.clear();
        service.removeTaskByPath('/path/song1.mp3'); //只剩 song1 被移除 → 位置 0
        expect(removed, [0]);
      } finally {
        PlaylistService.onTaskRemoved = null; //不泄漏到其他测试
      }
    });
  });

  group('歌单播放链路复现（V1.1-3 用户反馈）', () {
    late List<Song> lib;

    setUp(() {
      lib = [
        Song(
            name: 'a',
            audioFilePath: '/p/a.mp3',
            sortNumber: 1,
            addTime: DateTime(2026, 1, 1).toIso8601String()),
        Song(
            name: 'b',
            audioFilePath: '/p/b.mp3',
            sortNumber: 2,
            addTime: DateTime(2026, 1, 1).toIso8601String()),
        Song(
            name: 'c',
            audioFilePath: '/p/c.mp3',
            sortNumber: 3,
            addTime: DateTime(2026, 1, 1).toIso8601String()),
      ];
    });

    test('顺序模式：歌单源点击歌曲后队列为完整歌单', () async {
      service.resetForTest(
          mode: PlayMode.sequence, source: PlaySource.allSongs);
      service.updatePlaylists([
        Playlist(
            id: 'p1',
            name: 'P',
            createTime: DateTime(2026, 1, 1).toIso8601String(),
            songFilePaths: const ['/p/a.mp3', '/p/b.mp3', '/p/c.mp3']),
      ]);
      service.updateLibrary(lib); //同步库引用（不碰磁盘，init 的等价前置）
      //歌单页点击 b（模拟 _onSongTap：先切源）
      await service.setPlaySource(PlaySource.playlist, playlistId: 'p1');
      service.moveTo('/p/b.mp3');
      expect(service.tasks.map((t) => t.songFilePath).toList(),
          ['/p/a.mp3', '/p/b.mp3', '/p/c.mp3']);
      expect(service.currentIndex, 1);
      //再点 c：仍在完整歌单内定位
      service.moveTo('/p/c.mp3');
      expect(service.tasks.map((t) => t.songFilePath).toList(),
          ['/p/a.mp3', '/p/b.mp3', '/p/c.mp3']);
      expect(service.currentIndex, 2);
    });

    test('随机模式：歌单源点击歌曲后批次非空且目标歌在队首', () async {
      service.resetForTest(
          mode: PlayMode.realRandom, source: PlaySource.allSongs);
      service.updatePlaylists([
        Playlist(
            id: 'p1',
            name: 'P',
            createTime: DateTime(2026, 1, 1).toIso8601String(),
            songFilePaths: const ['/p/a.mp3', '/p/b.mp3', '/p/c.mp3']),
      ]);
      service.updateLibrary(lib); //同步库引用（不碰磁盘，init 的等价前置）
      await service.setPlaySource(PlaySource.playlist, playlistId: 'p1');
      service.moveTo('/p/b.mp3');
      expect(service.tasks, isNotEmpty);
      expect(service.tasks.first.songFilePath, '/p/b.mp3');
    });

    test('歌单不存在（歌单数据未同步）：顺序队列追加单曲、随机为空', () async {
      //复现"PlaylistService 拿不到歌单数据"的最坏场景
      service.resetForTest(
          mode: PlayMode.sequence, source: PlaySource.allSongs);
      service.updatePlaylists(const []); //歌单数据缺失
      service.updateLibrary(lib); //同步库引用（不碰磁盘，init 的等价前置）
      await service.setPlaySource(PlaySource.playlist, playlistId: 'gone');
      service.moveTo('/p/b.mp3');
      //顺序：队列只剩点击的那首（这正是用户看到的现象）
      expect(service.tasks.map((t) => t.songFilePath).toList(), ['/p/b.mp3']);
    });
  });
}

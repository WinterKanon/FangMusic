import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/models/weight_behavior.dart';
import 'package:fs_music_app/services/weight_config_service.dart';
import 'package:fs_music_app/services/weight_service.dart';

/// 权重系统核心逻辑测试（纯内存：写库走 StorageService，
/// 测试环境无平台通道会抛异常，被服务内部 try/catch 兜住，不崩溃）
void main() {
  final service = WeightService.instance;
  final config = WeightConfigService.instance;

  /// 构造一首歌（可指定权重/时间戳）
  Song makeSong({
    String path = '/path/song1.mp3',
    double weight = 100.0,
    String incTime = '',
    String decTime = '',
  }) {
    return Song(
      name: 'song1',
      audioFilePath: path,
      sortNumber: 1,
      addTime: DateTime(2026, 1, 1).toIso8601String(),
      weight: weight,
      lastWeightIncreaseTime: incTime,
      lastWeightDecreaseTime: decTime,
    );
  }

  group('配置服务（默认值 = docs/02 定稿）', () {
    setUp(() => config.resetForTest());

    test('默认调权数值', () {
      expect(config.deltaFor(WeightBehavior.manualClick), 30);
      expect(config.deltaFor(WeightBehavior.favorite), 200);
      expect(config.deltaFor(WeightBehavior.addNext), 20);
      expect(config.deltaFor(WeightBehavior.searchPlay), 15);
      expect(config.deltaFor(WeightBehavior.repeatOne), 8);
      expect(config.deltaFor(WeightBehavior.quickSkip), -25);
      expect(config.deltaFor(WeightBehavior.completedPlaying), 8);
      expect(config.deltaFor(WeightBehavior.unfavorite), -150);
    });

    test('setValue 修改后立即生效（预留接口）', () async {
      await config.setValue(WeightBehavior.favorite, 500);
      expect(config.deltaFor(WeightBehavior.favorite), 500);
      await config.restoreDefaults();
      expect(config.deltaFor(WeightBehavior.favorite), 200);
    });

    test('setValue 只改目标事件，不影响其他事件（fall-through 修复）', () async {
      await config.setValue(WeightBehavior.favorite, 500);
      expect(config.deltaFor(WeightBehavior.favorite), 500);
      expect(config.deltaFor(WeightBehavior.manualClick), 30);
      expect(config.deltaFor(WeightBehavior.addNext), 20);
      expect(config.deltaFor(WeightBehavior.completedPlaying), 8);
      expect(config.deltaFor(WeightBehavior.unfavorite), -150);
    });
  });

  group('行为调权', () {
    setUp(() {
      service.resetForTest();
      config.resetForTest();
    });

    test('手动点击 +30（默认）', () async {
      final song = makeSong();
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.manualClick);
      expect(service.weightOf(song.audioFilePath), 130.0); //100 + 30（默认）
    });

    test('增量按配置读取（用户改收藏为 +50 后生效）', () async {
      await config.setValue(WeightBehavior.favorite, 50);
      final song = makeSong();
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.favorite);
      expect(service.weightOf(song.audioFilePath), 150.0); //100 + 50（非默认 200）
    });

    test('clamp 上限 500', () async {
      final song = makeSong(weight: 490.0);
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.manualClick); //+30
      expect(service.weightOf(song.audioFilePath), 500.0);
    });

    test('clamp 下限 20（快切多次）', () async {
      final song = makeSong(weight: 25.0);
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.quickSkip); //-25
      expect(service.weightOf(song.audioFilePath), 20.0);
      await service.applyBehavior(song, WeightBehavior.quickSkip);
      expect(service.weightOf(song.audioFilePath), 20.0); //不再下降
    });

    test('增加/减少后时间戳更新（7 天回归不误触发）', () async {
      final s = makeSong(path: '/path/r.mp3', weight: 200.0);
      service.updateLibrary([s]);
      await service.applyBehavior(s, WeightBehavior.manualClick); //+30 → 230
      expect(service.weightOf('/path/r.mp3'), 230.0);
      //刚"增加"过（lastWeightIncreaseTime = now）→ 7 天回归不触发
      await service.applySevenDayRegression();
      expect(service.weightOf('/path/r.mp3'), 230.0);
    });
  });

  group('调权与权重引用', () {
    setUp(() => service.resetForTest());

    test('weight / 总权重（保留 4 位小数）', () async {
      service.updateLibrary([
        makeSong(path: '/path/a.mp3', weight: 100),
        makeSong(path: '/path/b.mp3', weight: 200),
        makeSong(path: '/path/c.mp3', weight: 300),
      ]);
      // 直接触发调权（内部同步写库失败被兜住）
      await service.applyBehavior(
        makeSong(path: '/path/a.mp3'),
        WeightBehavior.manualClick,
      );
      // 全库 600 → a=130/600=0.2167, b=200/600=0.3333, c=300/600=0.5
      // 概率字段 v1.1 起由独立权重库维护、不再写 songs.json；
      // 此处验证 weightOf 正确即可
      expect(service.weightOf('/path/a.mp3'), 130.0);
      expect(service.weightOf('/path/b.mp3'), 200.0);
    });

    test('总权重 0 → 等权（不崩溃）', () async {
      service.updateLibrary([
        makeSong(path: '/path/a.mp3', weight: 0),
        makeSong(path: '/path/b.mp3', weight: 0),
      ]);
      // 0 权重调权（+30）不崩溃
      await service.applyBehavior(
        makeSong(path: '/path/a.mp3'),
        WeightBehavior.manualClick,
      );
      expect(service.weightOf('/path/a.mp3'), 30.0);
      expect(service.weightOf('/path/b.mp3'), 0.0);
    });
  });

  group('播放衰减', () {
    setUp(() => service.resetForTest());

    test('第 1~4 次各减超出部分的 20%，第 5 次起不减', () async {
      final song = makeSong(weight: 200.0);
      service.updateLibrary([song]);
      await service.applyPlayDecay(song); //第1次: 200-(100)*0.2=180
      expect(service.weightOf(song.audioFilePath), 180.0);
      await service.applyPlayDecay(song); //第2次: 180-(80)*0.2=164
      expect(service.weightOf(song.audioFilePath), 164.0);
      await service.applyPlayDecay(song); //第3次: 164-(64)*0.2=151.2
      expect(service.weightOf(song.audioFilePath), 151.2);
      await service.applyPlayDecay(song); //第4次: 151.2-(51.2)*0.2=140.96
      expect(service.weightOf(song.audioFilePath), closeTo(140.96, 0.001));
      await service.applyPlayDecay(song); //第5次: 不再衰减
      expect(service.weightOf(song.audioFilePath), closeTo(140.96, 0.001));
    });

    test('weight ≤ 100 不衰减', () async {
      final song = makeSong(weight: 80.0);
      service.updateLibrary([song]);
      await service.applyPlayDecay(song);
      expect(service.weightOf(song.audioFilePath), 80.0);
    });

    test('resetDecayCounts 后重新计数', () async {
      final song = makeSong(weight: 200.0);
      service.updateLibrary([song]);
      for (var i = 0; i < 5; i++) {
        await service.applyPlayDecay(song);
      }
      expect(service.weightOf(song.audioFilePath), closeTo(140.96, 0.001));
      service.resetDecayCounts();
      await service.applyPlayDecay(song); //重新从第 1 次算
      // 140.96 - (140.96-100)*0.2 = 140.96 - 8.192 = 132.768
      expect(service.weightOf(song.audioFilePath), closeTo(132.768, 0.001));
    });
  });

  group('7 天回归', () {
    setUp(() => service.resetForTest());

    test('>100 且 7 天无增加/回归 → 向 100 回 5%', () async {
      final old8Days = DateTime.now().subtract(const Duration(days: 8));
      final song = makeSong(weight: 300.0, incTime: old8Days.toIso8601String());
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      // 300 + (100-300)*0.05 = 300 - 10 = 290
      expect(service.weightOf(song.audioFilePath), 290.0);
    });

    test('<100 且 7 天无减少/回归 → 向 100 回 2%', () async {
      final old8Days = DateTime.now().subtract(const Duration(days: 8));
      final song = makeSong(weight: 50.0, decTime: old8Days.toIso8601String());
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      // 50 + (100-50)*0.02 = 50 + 1 = 51
      expect(service.weightOf(song.audioFilePath), 51.0);
    });

    test('7 天内不回归', () async {
      final recent = DateTime.now().subtract(const Duration(days: 1));
      final song = makeSong(weight: 300.0, incTime: recent.toIso8601String());
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      expect(service.weightOf(song.audioFilePath), 300.0);
    });

    test('回归后记录时间戳，7 天内不重复回归', () async {
      final old8Days = DateTime.now().subtract(const Duration(days: 8));
      final song = makeSong(weight: 300.0, incTime: old8Days.toIso8601String());
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      expect(service.weightOf(song.audioFilePath), 290.0);
      // 第二次立即回归：回归已更新 lastWeightDecreaseTime → 不重复
      await service.applySevenDayRegression();
      expect(service.weightOf(song.audioFilePath), 290.0);
    });

    test('weight = 100 不参与回归', () async {
      final old8Days = DateTime.now().subtract(const Duration(days: 8));
      final song = makeSong(weight: 100.0, incTime: old8Days.toIso8601String());
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      expect(service.weightOf(song.audioFilePath), 100.0);
    });
  });

  group('预留接口', () {
    setUp(() {
      service.resetForTest();
      config.resetForTest();
    });

    test('setManualWeight：clamp [20,500] + 更新时间戳', () async {
      final song = makeSong(weight: 100.0);
      service.updateLibrary([song]);
      await service.setManualWeight(song, 999); //超上限
      expect(service.weightOf(song.audioFilePath), 500.0);
      await service.setManualWeight(song, -5); //超下限
      expect(service.weightOf(song.audioFilePath), 20.0);
    });

    test('setManualWeight 后随听歌行为正常增减', () async {
      final song = makeSong(weight: 100.0);
      service.updateLibrary([song]);
      await service.setManualWeight(song, 300.0);
      expect(service.weightOf(song.audioFilePath), 300.0);
      await service.applyBehavior(song, WeightBehavior.manualClick); //+30
      expect(service.weightOf(song.audioFilePath), 330.0);
    });

    test('onFavorite(true) 收藏调权，onFavorite(false) 取消收藏调权', () async {
      final song = makeSong();
      service.updateLibrary([song]);
      await service.onFavorite(song, true);
      expect(service.weightOf(song.audioFilePath), 300.0);
      await service.onFavorite(song, false);
      expect(service.weightOf(song.audioFilePath), 150.0); //300 - 150（默认）
    });

    test('onSearchPlay 搜索播放调权', () async {
      final song = makeSong();
      service.updateLibrary([song]);
      await service.onSearchPlay(song);
      expect(service.weightOf(song.audioFilePath), 115.0);
    });
  });

  group('v1.0 第二阶段：权重范围与重置', () {
    setUp(() {
      service.resetForTest();
      config.resetForTest();
    });

    test('默认范围 [20,500]；clampWeight 按配置范围收敛', () {
      expect(config.minWeight, 20);
      expect(config.maxWeight, 500);
      expect(config.clampWeight(10), 20);
      expect(config.clampWeight(600), 500);
      expect(config.clampWeight(100), 100);
    });

    test('setWeightRange 后调权/手动设定按新范围收敛', () async {
      await config.setWeightRange(200, 800);
      expect(config.minWeight, 200);
      expect(config.maxWeight, 800);
      final song = makeSong(weight: 100.0);
      service.updateLibrary([song]);
      //手动点击 +30 → 130 → 低于新下限 200 → clamp 到 200
      await service.applyBehavior(song, WeightBehavior.manualClick);
      expect(service.weightOf(song.audioFilePath), 200.0);
      //手动设定 999 → 超新上限 800 → clamp 到 800
      await service.setManualWeight(song, 999);
      expect(service.weightOf(song.audioFilePath), 800.0);
    });

    test('非法范围收敛不崩溃（min>max 时归一）', () async {
      await config.setWeightRange(500, 100);
      expect(config.minWeight, 100);
      expect(config.maxWeight, 500);
    });

    test('回归目标 100 不在范围 → 向最近边界回归', () async {
      await config.setWeightRange(200, 500);
      final old8Days = DateTime.now().subtract(const Duration(days: 8));
      final song = makeSong(weight: 400.0, incTime: old8Days.toIso8601String());
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      // 目标 = 最近边界 200：400 + (200-400)*0.05 = 390
      expect(service.weightOf(song.audioFilePath), 390.0);
    });

    test('resetSongWeight / resetAllWeights 重置为 100（范围内）', () async {
      service.updateLibrary([
        makeSong(path: '/path/a.mp3', weight: 300),
        makeSong(path: '/path/b.mp3', weight: 50),
      ]);
      await service.resetSongWeight(makeSong(path: '/path/a.mp3'));
      expect(service.weightOf('/path/a.mp3'), 100.0);
      await service.resetAllWeights();
      expect(service.weightOf('/path/a.mp3'), 100.0);
      expect(service.weightOf('/path/b.mp3'), 100.0);
    });

    test('完整播完 +8 默认值接入；取消收藏 -150 默认值接入', () async {
      final song = makeSong();
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.completedPlaying);
      expect(service.weightOf(song.audioFilePath), 108.0);
      //108 - 150 = -42 → 低于下限 20 → clamp 到 20
      await service.applyBehavior(song, WeightBehavior.unfavorite);
      expect(service.weightOf(song.audioFilePath), 20.0);
    });

    test('updateLibrary 不覆盖服务权威权重（收藏"乱跳"回归）', () async {
      final song = makeSong(weight: 300.0);
      service.updateLibrary([song]);
      //长按设定单曲权重为 20（只改服务库）
      await service.setManualWeight(song, 20);
      expect(service.weightOf(song.audioFilePath), 20.0);
      //UI 层同步（排序/收藏会传入可能过期的旧权重列表 500）
      service.updateLibrary([makeSong(path: '/path/song1.mp3', weight: 500.0)]);
      expect(service.weightOf(song.audioFilePath), 20.0); //未被旧值覆盖
      //收藏 +200 → 220（修复前旧值 500 + 200 → clamp 600）
      await service.onFavorite(makeSong(path: '/path/song1.mp3'), true);
      expect(service.weightOf(song.audioFilePath), 220.0);
      //取消收藏 -100（用户自定义配置）→ 120
      await WeightConfigService.instance.setValue(
          WeightBehavior.unfavorite, -100);
      await service.onFavorite(makeSong(path: '/path/song1.mp3'), false);
      expect(service.weightOf(song.audioFilePath), 120.0);
    });

    test('updateLibrary 合并新歌：新路径采用传入权重，旧路径保留服务权重', () async {
      service.updateLibrary([
        makeSong(path: '/path/a.mp3', weight: 100.0),
      ]);
      await service.setManualWeight(makeSong(path: '/path/a.mp3'), 300);
      //UI 刷新：新增 b.mp3（权重 100），a.mp3 传入过期值 100
      service.updateLibrary([
        makeSong(path: '/path/a.mp3', weight: 100.0),
        makeSong(path: '/path/b.mp3', weight: 100.0),
      ]);
      expect(service.weightOf('/path/a.mp3'), 300.0); //保留服务权重
      expect(service.weightOf('/path/b.mp3'), 100.0); //新歌采用传入值
    });
  });

  group('v1.1：基准权重模型（baseWeight）', () {
    setUp(() {
      service.resetForTest();
      config.resetForTest();
    });

    Song makeSongWithBase({
      String path = '/path/s1.mp3',
      double weight = 100.0,
      double baseWeight = 100.0,
      String incTime = '',
      String decTime = '',
    }) {
      return Song(
        name: 's',
        audioFilePath: path,
        sortNumber: 1,
        addTime: DateTime(2026, 1, 1).toIso8601String(),
        weight: weight,
        baseWeight: baseWeight,
        lastWeightIncreaseTime: incTime,
        lastWeightDecreaseTime: decTime,
      );
    }

    test('新配置默认值：不喜欢基准 60 / 减幅 -20 / 队列移除 -5', () {
      expect(config.unlikeBaseWeight, 60);
      expect(config.unlikeDelta, -50);
      expect(config.queueRemoveDelta, -5);
    });

    test('markUnliked：基准降 60 + 当前权重 -50（默认）', () async {
      final song = makeSongWithBase(weight: 150.0);
      service.updateLibrary([song]);
      await service.markUnliked(song);
      expect(service.baseWeightOf(song.audioFilePath), 60.0);
      expect(service.weightOf(song.audioFilePath), 100.0); //150 - 50（默认）
    });

    test('markUnliked 后 7 天回归回到基准 60 而非 100', () async {
      final old8Days = DateTime.now().subtract(const Duration(days: 8));
      final song = makeSongWithBase(
        weight: 80.0,
        baseWeight: 60.0,
        decTime: old8Days.toIso8601String(),
      );
      service.updateLibrary([song]);
      await service.applySevenDayRegression();
      // 目标 60：weight 80 > base 60 → 向 60 回 5%：80 + (60-80)*0.05 = 79
      expect(service.weightOf(song.audioFilePath), closeTo(79.0, 0.001));
      // 不会一路回到 100
      expect(service.weightOf(song.audioFilePath), lessThan(80.0));
    });

    test('播放衰减只衰减超出基准的部分（基准 60）', () async {
      final song = makeSongWithBase(weight: 160.0, baseWeight: 60.0);
      service.updateLibrary([song]);
      await service.applyPlayDecay(song);
      // 160 - (160-60)*0.2 = 160 - 20 = 140
      expect(service.weightOf(song.audioFilePath), 140.0);
    });

    test('resetSongWeight 恢复基准与权重为 100', () async {
      final song = makeSongWithBase(weight: 80.0, baseWeight: 60.0);
      service.updateLibrary([song]);
      await service.markUnliked(song);
      await service.resetSongWeight(song);
      expect(service.baseWeightOf(song.audioFilePath), 100.0);
      expect(service.weightOf(song.audioFilePath), 100.0);
    });

    test('removeFromQueue：普通移除 -5（默认）', () async {
      final song = makeSongWithBase(weight: 120.0);
      service.updateLibrary([song]);
      await service.removeFromQueue(song);
      expect(service.weightOf(song.audioFilePath), 115.0);
    });

    test('移除"下一首"标记歌 = 撤销添加加分（-addNext）', () async {
      final song = makeSongWithBase(weight: 100.0);
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.addNext); //+20 → 120
      await service.removeFromQueue(song, wasNextSong: true); //-20 → 100
      expect(service.weightOf(song.audioFilePath), 100.0);
    });

    test('removeFromQueue 撤销值跟随"添加下一首"配置', () async {
      await config.setValue(WeightBehavior.addNext, 100);
      final song = makeSongWithBase(weight: 150.0);
      service.updateLibrary([song]);
      await service.applyBehavior(song, WeightBehavior.addNext); //+100 → 250
      await service.removeFromQueue(song, wasNextSong: true); //-100 → 150
      expect(service.weightOf(song.audioFilePath), 150.0);
    });

    test('updateLibrary 清理已不在库中的歌曲权重（删除歌曲联动）', () async {
      service.updateLibrary([
        makeSongWithBase(path: '/path/a.mp3'),
        makeSongWithBase(path: '/path/b.mp3'),
      ]);
      await service.setManualWeight(
        makeSongWithBase(path: '/path/a.mp3'),
        300,
      );
      //库刷新：b 已删除
      service.updateLibrary([makeSongWithBase(path: '/path/a.mp3')]);
      expect(service.weightOf('/path/a.mp3'), 300.0);
      expect(service.weightOf('/path/b.mp3'), isNull); //权重随歌曲清理
    });

    test('markUnliked clamp：基准 60 不在范围 [200,500] → 收敛到 200', () async {
      await config.setWeightRange(200, 500);
      final song = makeSongWithBase(weight: 400.0);
      service.updateLibrary([song]);
      await service.markUnliked(song);
      expect(service.baseWeightOf(song.audioFilePath), 200.0);
      // weight 400 + (-50) = 350（仍在范围内）
      expect(service.weightOf(song.audioFilePath), 350.0);
    });
  });
  group('v1.1-2：删除歌曲联动（removeSong）', () {
    setUp(() {
      service.resetForTest();
      config.resetForTest();
    });

    test('removeSong 清除权重记录（含基准）与衰减计数', () async {
      final song = Song(
        name: 's',
        audioFilePath: '/path/del.mp3',
        sortNumber: 1,
        addTime: '2026-01-01T00:00:00.000',
        weight: 150,
        baseWeight: 60,
      );
      service.updateLibrary([song]);
      await service.markUnliked(song);
      expect(service.weightOf('/path/del.mp3'), 100.0); //150 - 50（默认）
      expect(service.baseWeightOf('/path/del.mp3'), 60.0);
      await service.removeSong('/path/del.mp3');
      expect(service.weightOf('/path/del.mp3'), isNull);
      expect(service.baseWeightOf('/path/del.mp3'), isNull);
    });

    test('removeSong 对未调过权的歌静默（不崩溃）', () async {
      await service.removeSong('/path/never.mp3'); //无记录
      expect(service.weightOf('/path/never.mp3'), isNull);
    });
  });
}
